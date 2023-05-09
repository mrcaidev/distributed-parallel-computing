#include <math.h>
#include <stdio.h>
#include <stdlib.h>
#include "timer.h"
#include "check.h"
#include <cuda_runtime.h>

#define SOFTENING 1e-9f
#define BLOCK_SIZE 32

/*
 * Each body contains x, y, and z coordinate positions,
 * as well as velocities in the x, y, and z directions.
 */

typedef struct
{
    float x, y, z, vx, vy, vz;
} Body;

/*
 * Do not modify this function. A constraint of this exercise is
 * that it remain a host function.
 */

void randomizeBodies(float *data, int n)
{
    for (int i = 0; i < n; i++)
    {
        data[i] = 2.0f * (rand() / (float)RAND_MAX) - 1.0f;
    }
}

/*
 * This function calculates the gravitational impact of all bodies in the system
 * on all others, but does not update their positions.
 */

__global__ void bodyForce(Body *p, float dt, int n)
{

    int i = threadIdx.x + blockIdx.x / BLOCK_SIZE * blockDim.x;

    if (i >= n)
    {
        return;
    }

    __shared__ float3 cache[BLOCK_SIZE];

    float Fx = 0.0f;
    float Fy = 0.0f;
    float Fz = 0.0f;

    for (int k = blockIdx.x % BLOCK_SIZE; k < n / BLOCK_SIZE; k += BLOCK_SIZE)
    {
        Body applier = p[k * BLOCK_SIZE + threadIdx.x];
        cache[threadIdx.x] = make_float3(applier.x, applier.y, applier.z);

        // __syncthreads();

        for (int j = 0; j < BLOCK_SIZE; j++)
        {
            float dx = cache[j].x - p[i].x;
            float dy = cache[j].y - p[i].y;
            float dz = cache[j].z - p[i].z;
            float distSqr = dx * dx + dy * dy + dz * dz + SOFTENING;
            float invDist = rsqrtf(distSqr);
            float invDist3 = invDist * invDist * invDist;

            Fx += dx * invDist3;
            Fy += dy * invDist3;
            Fz += dz * invDist3;
        }

        // __syncthreads();
    }

    atomicAdd(&p[i].vx, dt * Fx);
    atomicAdd(&p[i].vy, dt * Fy);
    atomicAdd(&p[i].vz, dt * Fz);
}

__global__ void integratePosition(Body *p, float dt, int n)
{
    int i = threadIdx.x + blockIdx.x * blockDim.x;

    if (i >= n)
    {
        return;
    }

    p[i].x += p[i].vx * dt;
    p[i].y += p[i].vy * dt;
    p[i].z += p[i].vz * dt;
}

int main(const int argc, const char **argv)
{

    /*
     * Do not change the value for `nBodies` here. If you would like to modify it,
     * pass values into the command line.
     */

    int nBodies = 2 << 11;
    int salt = 0;
    if (argc > 1)
        nBodies = 2 << atoi(argv[1]);

    /*
     * This salt is for assessment reasons. Tampering with it will result in automatic failure.
     */

    if (argc > 2)
        salt = atoi(argv[2]);

    const float dt = 0.01f; // time step
    const int nIters = 10;  // simulation iterations

    int bytes = nBodies * sizeof(Body);
    float *buf;

    cudaMallocHost(&buf, bytes);

    /*
     * As a constraint of this exercise, `randomizeBodies` must remain a host function.
     */

    randomizeBodies(buf, 6 * nBodies); // Init pos / vel data

    double totalTime = 0.0;

    int nBlocks = (nBodies + BLOCK_SIZE - 1) / BLOCK_SIZE;

    float *dBuf;
    cudaMalloc(&dBuf, bytes);

    Body *dp = (Body *)dBuf;
    cudaMemcpy(dBuf, buf, bytes, cudaMemcpyHostToDevice);

    /*
     * This simulation will run for 10 cycles of time, calculating gravitational
     * interaction amongst bodies, and adjusting their positions to reflect.
     */

    /*******************************************************************/
    // Do not modify these 2 lines of code.gg
    for (int iter = 0; iter < nIters; iter++)
    {
        StartTimer();
        /*******************************************************************/

        /*
         * You will likely wish to refactor the work being done in `bodyForce`,
         * as well as the work to integrate the positions.
         */

        bodyForce<<<nBlocks * BLOCK_SIZE, BLOCK_SIZE>>>(dp, dt, nBodies); // compute interbody forces

        /*
         * This position integration cannot occur until this round of `bodyForce` has completed.
         * Also, the next round of `bodyForce` cannot begin until the integration is complete.
         */
        integratePosition<<<nBodies / BLOCK_SIZE, BLOCK_SIZE>>>(dp, dt, nBodies);

        if (iter == nIters - 1)
        {
            cudaMemcpy(buf, dBuf, bytes, cudaMemcpyDeviceToHost);
        }

        /*******************************************************************/
        // Do not modify the code in this section.
        const double tElapsed = GetTimer() / 1000.0;
        totalTime += tElapsed;
    }

    double avgTime = totalTime / (double)(nIters);
    float billionsOfOpsPerSecond = 1e-9 * nBodies * nBodies / avgTime;

#ifdef ASSESS
    checkPerformance(buf, billionsOfOpsPerSecond, salt);
#else
    checkAccuracy(buf, nBodies);
    printf("%d Bodies: average %0.3f Billion Interactions / second\n", nBodies, billionsOfOpsPerSecond);
    salt += 1;
#endif
    /*******************************************************************/

    /*
     * Feel free to modify code below.
     */

    cudaFree(dBuf);
    cudaFreeHost(buf);
}
