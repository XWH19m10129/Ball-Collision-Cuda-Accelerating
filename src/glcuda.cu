#include "cuda_runtime.h"
#include "device_launch_parameters.h"
#include <stdio.h>
#include <iostream>
#include <stdlib.h>
#include <cmath>
#include <sys/stat.h>
#include <sys/types.h>
#include "sphere.cuh"

#define PI 3.1415926536
#define GRIDSPHERES 27
const int SPACESIZE = 10; // �ռ��С
Sphere* spheres;
Sphere* d_spheres;
const int SPHERE_NUMBER = 64*4; // С������
const float TIMEPERFRAME = 0.1; // ��������
const float gravity = -0.07 * TIMEPERFRAME; // ������С
#define collisionEpsilon 0.08
int* gridContainSphereIndex;
int* gridContainSphereNumber;
int* d_gridContainSphereIndex;
int* d_gridContainSphereNumber;

// CUDA错误检查宏
#define CUDA_CHECK(call) \
    do { \
        cudaError_t error = call; \
        if (error != cudaSuccess) { \
            fprintf(stderr, "CUDA Error: %s:%d, ", __FILE__, __LINE__); \
            fprintf(stderr, "code: %d, reason: %s\n", error, cudaGetErrorString(error)); \
            exit(1); \
        } \
    } while(0)

__host__ __device__ float myMax(float a, float b)
{
    return a > b ? a : b;
}
__host__ __device__ float myMin(float a, float b)
{
    return a > b ? b : a;
}
__host__ __device__ int getIndexGCSN(int a, int b, int c)
{
    return c + b * SPACESIZE + a * SPACESIZE * SPACESIZE;
}
__host__ __device__ int getIndexGCSI(int a, int b, int c, int d)
{
    return d + c * GRIDSPHERES + b * GRIDSPHERES * SPACESIZE + a * GRIDSPHERES * SPACESIZE * SPACESIZE;
}

// �ռ仮��
__global__ void sphereGridIndex(Sphere* d_spheres, int* d_gridContainSphereIndex, int* d_gridContainSphereNumber, int SPHERE_NUMBER)
{
    // ��ȡȫ������
    int index = threadIdx.x + blockIdx.x * blockDim.x;
    // ����
    int stride = blockDim.x * gridDim.x;
    for (int i = index; i < SPHERE_NUMBER; i += stride)
    {
        Vec3f location(d_spheres[i].center);
        int geshu = atomicAdd(&(d_gridContainSphereNumber[getIndexGCSN(abs((int)location.x()),abs((int)location.y()),abs((int)location.z()))]),1);
        d_gridContainSphereIndex[getIndexGCSI(abs((int)location.x()), abs((int)location.y()), abs((int)location.z()), geshu)] = i;
    }
}
// ��ײ���
__global__ void sphereGridCollision(Sphere* d_spheres, int* d_gridContainSphereIndex, int* d_gridContainSphereNumber, int SPHERE_NUMBER, float gravity)
{
    // ��ȡȫ������
    int index = threadIdx.x + blockIdx.x * blockDim.x;
    // ����
    int stride = blockDim.x * gridDim.x;
    for (int i = index; i < SPHERE_NUMBER; i += stride)
    {
        d_spheres[i].speed += Vec3f(0, gravity, 0);
        Sphere& theSphere = (d_spheres[i]);
        Vec3f location(d_spheres[i].center);
        float radius = d_spheres[i].radius;
        Vec3f& speed = (d_spheres[i].speed);
        float restitution = d_spheres[i].restitution;
        float mass = theSphere.mass;
        // ��ǽ��ײ
        if (location[0] - radius <= 0)
        {
            d_spheres[i].speed.Set(abs(restitution * speed[0]), speed[1], speed[2]);
            speed = d_spheres[i].speed;
        }
        if (location[1] - radius <= 0)
        {
            d_spheres[i].speed.Set(speed[0], abs(restitution * speed[1]), speed[2]);
            speed = d_spheres[i].speed;
        }
        if (location[2] - radius <= 0)
        {
            d_spheres[i].speed.Set(speed[0], speed[1], abs(restitution * speed[2]));
            speed = d_spheres[i].speed;
        }
        if (location[0] + radius >= SPACESIZE)
        {
            d_spheres[i].speed.Set(-abs(restitution * speed[0]), speed[1], speed[2]);
            speed = d_spheres[i].speed;
        }
        if (location[1] + radius >= SPACESIZE)
        {
            d_spheres[i].speed.Set(speed[0], -abs(restitution * speed[1]), speed[2]);
            speed = d_spheres[i].speed;
        }
        if (location[2] + radius >= SPACESIZE)
        {
            d_spheres[i].speed.Set(speed[0], speed[1], -abs(restitution * speed[2]));
            speed = d_spheres[i].speed;
        }

        //����������ײ
        for (int m = myMax(location.x()-1, 0); m <= myMin(location.x() + 1, SPACESIZE-1); m++)
        {
            for (int n = myMax(location.y() - 1, 0); n <= myMin(location.y() + 1, SPACESIZE - 1); n++)
            {
                for (int o = myMax(location.z() - 1, 0); o <= myMin(location.z() + 1, SPACESIZE - 1); o++)
                {
                    //printf("d_gridContainSphereNumber[getIndexGCSN(m, n, o)]: %d\n", d_gridContainSphereNumber[getIndexGCSN(m, n, o)]);
                    for (int p = 0; p < d_gridContainSphereNumber[getIndexGCSN(m, n, o)]; p++)
                    {
                        int aimIndex = d_gridContainSphereIndex[getIndexGCSI(m, n, o, p)];
                        //printf("aimIndex%d, i%d\n", aimIndex, i);
                        if (aimIndex <= i) { continue; }
                        Sphere aimSphere = d_spheres[aimIndex];

                        Vec3f centerDistance(aimSphere.center - d_spheres[i].center);
                        //printf("pos0.0");
                        if (centerDistance.Length() > theSphere.radius + aimSphere.radius + collisionEpsilon) { continue; }
                        //printf("begin collision!");
                        // ������ײ


                        Vec3f aimSpeed(aimSphere.speed);
                        float aimMass = aimSphere.mass;
                        float collisionRestitution = (restitution + aimSphere.restitution) / 2;
                        
                        // ���ķ�����ٶ�
                        float fenSpeed = speed.Dot3(centerDistance) / centerDistance.Length();
                        float aimFenSpeed = aimSpeed.Dot3(centerDistance) / centerDistance.Length();

                        float fenSpeedFinal = (mass * fenSpeed + aimMass * aimFenSpeed + aimMass * collisionRestitution * (aimFenSpeed - fenSpeed) ) / (mass + aimMass);
                        float aimFenSpeedFinal = (mass * fenSpeed + aimMass * aimFenSpeed + mass * collisionRestitution * (fenSpeed - aimFenSpeed)) / (mass + aimMass);

                        float fenSpeedChangeB = fenSpeedFinal - fenSpeed; 
                        float aimFenSpeedChangeB = aimFenSpeedFinal - aimFenSpeed;
                        //printf("%f fenSpeed:%f, aimFenSpeed:%f, fenSpeedFinal:%f\n", fenSpeedFinal - fenSpeed, fenSpeed, aimFenSpeed, fenSpeedFinal);
                        Vec3f fenChangeSpeed(centerDistance * (fenSpeedChangeB / centerDistance.Length()));
                        Vec3f aimFenChangeSpeed(centerDistance * (aimFenSpeedChangeB / centerDistance.Length()));
                        /*printf("%f the:%f, %f, %f. aim: %f, %f, %f. change: %f, %f, %f\n" , fenSpeedFinal - fenSpeed,theSphere.center.x(), theSphere.center.y(), theSphere.center.z(),
                            aimSphere.center.x(), aimSphere.center.y(), aimSphere.center.z(), fenChangeSpeed.x(), fenChangeSpeed.y(), fenChangeSpeed.z());*/
                        d_spheres[i].speed += fenChangeSpeed;
                        d_spheres[aimIndex].speed += aimFenChangeSpeed;
                        speed = d_spheres[i].speed;
                    }
                }
            }
        }
    }
}
// С���ƶ�
__global__ void sphereMove(Sphere* d_spheres,int SPHERE_NUMBER, float TIMEPERFRAME)
{
    // ��ȡȫ������
    int index = threadIdx.x + blockIdx.x * blockDim.x;
    // ����
    int stride = blockDim.x * gridDim.x;
    for (int i = index; i < SPHERE_NUMBER; i += stride)
    {
        d_spheres[i].center += d_spheres[i].speed * TIMEPERFRAME;
    }
}
void initScene()
{
    spheres = (Sphere*)malloc(SPHERE_NUMBER * sizeof(Sphere));
    gridContainSphereIndex = (int *)malloc(SPACESIZE * SPACESIZE * SPACESIZE * GRIDSPHERES * sizeof(int));
    gridContainSphereNumber = (int *)malloc(SPACESIZE * SPACESIZE * SPACESIZE * sizeof(int));
    CUDA_CHECK(cudaMalloc((void**)&d_spheres, SPHERE_NUMBER * sizeof(Sphere)));
    CUDA_CHECK(cudaMalloc((void**)&d_gridContainSphereIndex, SPACESIZE*SPACESIZE*SPACESIZE * GRIDSPHERES * sizeof(int)));
    CUDA_CHECK(cudaMalloc((void**)&d_gridContainSphereNumber, SPACESIZE * SPACESIZE * SPACESIZE * sizeof(int)));
    for (int i = 0; i < SPHERE_NUMBER; i++)
    {
        spheres[i].center.Set(1.0 + i % 64 % 8, 4 + i/64, 1.0 + i % 64 / 8);
        spheres[i].radius = 0.25 + (rand() % 1000) / 1000.0 * 0.25;
        spheres[i].color.Set((rand() % 1000) / 1000.0, (rand() % 1000) / 1000.0, (rand() % 1000) / 1000.0);
        spheres[i].speed.Set((rand() % 1000) / 1000.0, (rand() % 1000) / 1000.0, (rand() % 1000) / 1000.0);
        spheres[i].restitution = 0.8 + (rand() % 1000) / 1000.0 * 0.2; 
        spheres[i].mass = spheres[i].radius * spheres[i].radius * spheres[i].radius;
    }
}

// 保存帧数据到CSV文件
void saveFrameData(int frameNumber) {
    char filename[256];
    sprintf(filename, "output/frame_%05d.csv", frameNumber);
    FILE* fp = fopen(filename, "w");
    
    if (fp == NULL) {
        fprintf(stderr, "Error: Cannot open file %s for writing\n", filename);
        return;
    }
    
    fprintf(fp, "id,x,y,z,vx,vy,vz,radius,r,g,b\n");
    for (int i = 0; i < SPHERE_NUMBER; i++) {
        fprintf(fp, "%d,%f,%f,%f,%f,%f,%f,%f,%f,%f,%f\n",
            i,
            spheres[i].center.x(), spheres[i].center.y(), spheres[i].center.z(),
            spheres[i].speed.x(), spheres[i].speed.y(), spheres[i].speed.z(),
            spheres[i].radius,
            spheres[i].color[0], spheres[i].color[1], spheres[i].color[2]
        );
    }
    fclose(fp);
}

// 执行一帧的物理模拟
void simulateFrame() {
    // 每一帧的碰撞检测和计算
    // 开始进行碰撞检测并更新场景
    dim3 blockSize(SPHERE_NUMBER);
    dim3 gridSize(1);
    
    memset(gridContainSphereIndex, 0, SPACESIZE * SPACESIZE * SPACESIZE * GRIDSPHERES * sizeof(int));
    memset(gridContainSphereNumber, 0, SPACESIZE * SPACESIZE * SPACESIZE * sizeof(int));

    CUDA_CHECK(cudaMemcpy((void*)d_gridContainSphereIndex, (void*)gridContainSphereIndex, SPACESIZE * SPACESIZE * SPACESIZE * GRIDSPHERES * sizeof(int), cudaMemcpyHostToDevice));
    CUDA_CHECK(cudaMemcpy((void*)d_gridContainSphereNumber, (void*)gridContainSphereNumber, SPACESIZE * SPACESIZE * SPACESIZE * sizeof(int), cudaMemcpyHostToDevice));
    CUDA_CHECK(cudaMemcpy((void*)d_spheres, (void*)spheres, SPHERE_NUMBER * sizeof(Sphere), cudaMemcpyHostToDevice));
    CUDA_CHECK(cudaDeviceSynchronize());
    
    sphereGridIndex << < gridSize, blockSize >> > (d_spheres, d_gridContainSphereIndex, d_gridContainSphereNumber, SPHERE_NUMBER);
    CUDA_CHECK(cudaGetLastError());
    CUDA_CHECK(cudaDeviceSynchronize());
    
    sphereGridCollision << < gridSize, blockSize >> > (d_spheres, d_gridContainSphereIndex, d_gridContainSphereNumber, SPHERE_NUMBER, gravity);
    CUDA_CHECK(cudaGetLastError());
    CUDA_CHECK(cudaDeviceSynchronize());
    
    sphereMove << < gridSize, blockSize >> > (d_spheres, SPHERE_NUMBER, TIMEPERFRAME);
    CUDA_CHECK(cudaGetLastError());
    CUDA_CHECK(cudaDeviceSynchronize());
   
    CUDA_CHECK(cudaMemcpy((void*)spheres, (void*)d_spheres, SPHERE_NUMBER * sizeof(Sphere), cudaMemcpyDeviceToHost));
    CUDA_CHECK(cudaDeviceSynchronize());
}

// 清理资源
void cleanup() {
    free(spheres);
    free(gridContainSphereIndex);
    free(gridContainSphereNumber);
    CUDA_CHECK(cudaFree(d_spheres));
    CUDA_CHECK(cudaFree(d_gridContainSphereIndex));
    CUDA_CHECK(cudaFree(d_gridContainSphereNumber));
}

int main(int argc, char* argv[])
{
    // 初始化场景
    srand(1);
    
    // 创建输出目录
    #ifdef _WIN32
    _mkdir("output");
    #else
    mkdir("output", 0755);
    #endif
    
    printf("初始化场景...\n");
    initScene();
    
    // 从命令行读取模拟帧数，默认1000帧
    int totalFrames = 1000;
    if (argc > 1) {
        totalFrames = atoi(argv[1]);
        if (totalFrames <= 0) {
            fprintf(stderr, "错误：帧数必须为正整数\n");
            cleanup();
            return 1;
        }
    }
    
    printf("开始模拟 %d 帧...\n", totalFrames);
    printf("球体数量: %d\n", SPHERE_NUMBER);
    printf("空间大小: %d x %d x %d\n", SPACESIZE, SPACESIZE, SPACESIZE);
    
    // 主循环
    for (int frame = 0; frame < totalFrames; frame++) {
        simulateFrame();
        
        // 每隔10帧保存一次数据
        if (frame % 10 == 0) {
            saveFrameData(frame);
            printf("已完成第 %d 帧 (%.1f%%)\n", frame, (float)frame / totalFrames * 100);
        }
    }
    
    // 保存最后一帧
    saveFrameData(totalFrames - 1);
    printf("模拟完成！\n");
    printf("输出文件保存在 output/ 目录\n");
    
    cleanup();
    return 0;
}