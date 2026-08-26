#include <stdio.h>
#include <stdint.h>
#include <fcntl.h>
#include <sys/mman.h>
#include <unistd.h>
#include <time.h>

// The hardware address map 
#define LW_BRIDGE_BASE 0xFF200000
#define MATMUL_OFFSET 0x00040000
#define SPAN 0x1000

// Avalon word addresses
#define REG_CONTROL_STATUS 0
#define REG_MAT_A 1
#define REG_MAT_B 65
#define REG_MAT_C 129
#define STATUS_BUSY (1u << 0)
#define STATUS_DONE (1u << 1)
#define FPGA_CLK_MHZ 97.368421

// Q8.8 / Q16.16 fixed-point conversions
static inline int16_t to_q8_8(double val)
{
    return (int16_t)(val * 256.0);
}

static inline double from_q16_16(int32_t val)
{
    return (double)val / 65536.0;
}

int main(void)
{
    int fd = open("/dev/mem", O_RDWR | O_SYNC);
    if (fd < 0)
    {
        perror("open /dev/mem");
        return 1;
    }

    volatile uint32_t *regs = mmap (
        NULL,
        SPAN,
        PROT_READ | PROT_WRITE,
        MAP_SHARED,
        fd,
        LW_BRIDGE_BASE + MATMUL_OFFSET
    );

    if (regs == MAP_FAILED)
    {
        perror("mmap");
        close(fd);
        return 1;
    }


    // Here we will make sure to start the accelerator from IDLE.
    regs[REG_CONTROL_STATUS] = 0; // Clear control register to ensure IDLE state

    // 8 x 8 matrix multiplication example
    double A[8][8];
    double B[8][8];

    for (int i = 0; i < 8; i++)
    {
        for (int j = 0; j < 8; j++)
        {
            A[i][j] = (i + j) % 8 + 1;
            B[i][j] = ((i * 2 + j) % 8) + 1;
        }
    }

    // Loading Matrix A
    for (int i = 0; i < 8; i++)
    {
        for (int j = 0; j < 8; j++)
        {
            regs[REG_MAT_A + i * 8 + j] = (uint16_t)to_q8_8(A[i][j]);
        }
    }

    // Loading Matrix B
    for (int i = 0; i < 8; i++)
    {
        for (int j = 0; j < 8; j++)
        {
            regs[REG_MAT_B + i * 8 + j] = (uint16_t)to_q8_8(B[i][j]);
        }
    }

    // Start the accelerator
    struct timespec t0, t1;
    clock_gettime(CLOCK_MONOTONIC, &t0);
    regs[REG_CONTROL_STATUS] = 1; // Set control register to start operation
    while (!(regs[REG_CONTROL_STATUS] & STATUS_DONE))
    {
        // Wait for the operation to complete
    }

    clock_gettime(CLOCK_MONOTONIC, &t1);
    double elapsed_us = (t1.tv_sec - t0.tv_sec) * 1e6 + (t1.tv_nsec - t0.tv_nsec) / 1e3; // in microseconds
    printf("HPS-visible accelerator latency: %.2f us\n", elapsed_us);
    printf("Equivalent to approximately %.0f FGPA clock periods at %.3f MHz\n", elapsed_us * FPGA_CLK_MHZ, FPGA_CLK_MHZ);

    // Reading Matrix C
    printf("\nResult Matrix C:\n");
    for (int i = 0; i < 8; i++)
    {
        for (int j = 0; j < 8; j++)
        {
            int32_t raw = (int32_t)regs[REG_MAT_C + i * 8 + j];
            printf("%8.2f ", from_q16_16(raw));
        }
        printf("\n");
    }

    // Deassert the control register to return to IDLE state
    regs[REG_CONTROL_STATUS] = 0;
    munmap((void *)regs, SPAN);
    close(fd);
    return 0;
}
