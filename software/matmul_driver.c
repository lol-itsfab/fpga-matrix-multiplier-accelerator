#include <stdio.h>
#include <stdint.h>
#include <fcntl.h>
#include <sys/mman.h>
#include <unistd.h>
#include <time.h>
#include <math.h>

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
#define FPGA_CLK_MHZ 50.0
#define TOLERANCE 0.001

// Q8.8 / Q16.16 fixed-point conversions
static inline int16_t to_q8_8(double val)
{
    return (int16_t)(val * 256.0);
}

static inline double from_q16_16(int32_t val)
{
    return (double)val / 65536.0;
}

// Function to calculate elapsed time in microseconds
static double elapsed_us(struct timespec start, struct timespec end)
{
    return (end.tv_sec - start.tv_sec) * 1e6 + (end.tv_nsec - start.tv_nsec) / 1e3;
}

// CPU matrix multiplication for verification
static void cpu_matmul (
    double A[8][8],
    double B[8][8],
    double C[8][8]
)
{
    for (int i = 0; i < 8; i++)
    {
        for (int j = 0; j < 8; j++)
        {
            C[i][j] = 0.0;
            for (int k = 0; k < 8; k++)
            {
                C[i][j] += A[i][k] * B[k][j];
            }
        }
    }
}

static double fpga_matmul (
    volatile uint32_t *regs,
    double A[8][8],
    double B[8][8],
    double C[8][8]
)
{
    regs[REG_CONTROL_STATUS] = 0; // Clear control register to ensure IDLE state for accelerator

    // This loads Matrix A
    for (int i = 0; i < 8; i++)
    {
        for (int j = 0; j < 8; j++)
        {
            regs[REG_MAT_A + i * 8 + j] = (uint16_t)to_q8_8(A[i][j]);
        }
    }

    // This loads Matrix B
    for (int i = 0; i < 8; i++)
    {
        for (int j = 0; j < 8; j++)
        {
            regs[REG_MAT_B + i * 8 + j] = (uint16_t)to_q8_8(B[i][j]);
        }
    }

    struct timespec fpga_t0, fpga_t1;
    clock_gettime(CLOCK_MONOTONIC, &fpga_t0);
    regs[REG_CONTROL_STATUS] = 1; // Set control register to start operation starting the FPGA accelerator
    while (!(regs[REG_CONTROL_STATUS] & STATUS_DONE))
    {
        // Wait for the FPGA computation to complete
    }
    clock_gettime(CLOCK_MONOTONIC, &fpga_t1);

    // This reads Matrix C
    for (int i = 0; i < 8; i++)
    {
        for (int j = 0; j < 8; j++)
        {
            int32_t raw = (int32_t)regs[REG_MAT_C + i * 8 + j];
            C[i][j] = from_q16_16(raw);
        }
    }
    regs[REG_CONTROL_STATUS] = 0; // Clear control register to return to IDLE state
    return elapsed_us(fpga_t0, fpga_t1);
}

static void print_matrix(
    const char *name,
    double matrix[8][8]
)
{
    printf("\n%s:\n", name);
    for (int i = 0; i < 8; i++)
    {
        for (int j = 0; j < 8; j++)
        {
            printf("%8.2f ", matrix[i][j]);
        }
        printf("\n");
    }
}

static int run_test (
    const char *test_name,
    volatile uint32_t *regs,
    double A[8][8],
    double B[8][8]
)
{
    double C_cpu[8][8];
    double C_fpga[8][8];

    // CPU computation for verification
    struct timespec cpu_t0, cpu_t1;
    clock_gettime(CLOCK_MONOTONIC, &cpu_t0);
    cpu_matmul(A, B, C_cpu);
    clock_gettime(CLOCK_MONOTONIC, &cpu_t1);
    double cpu_us = elapsed_us(cpu_t0, cpu_t1);

    // FPGA computation
    double fpga_us = fpga_matmul(regs, A, B, C_fpga);

    // Verify FPGA result against CPU result
    int pass = 1;
    double max_error = 0.0;
    for (int i = 0; i < 8; i++)
    {
        for (int j = 0; j < 8; j++)
        {
            double error = fabs(C_fpga[i][j] - C_cpu[i][j]);
            if (error > max_error)
            {
                max_error = error;
            }

            if (error > TOLERANCE)
            {
                pass = 0;
            }
        }
    }

    // Print results and performance metrics
    printf("\n==========================================\n");
    printf("Test: %s\n", test_name);
    printf("\n===========================================\n");
    print_matrix("FPGA Result Matrix C", C_fpga);
    print_matrix("CPU Result Matrix C", C_cpu);
    printf("\nVerification: %s\n", pass ? "PASS" : "FAIL");
    printf("Maximum error: %.6f\n", max_error);
    printf("\nCPU matrix multiply latency: %.2f us\n", cpu_us);
    printf("FPGA HPS-visible latency: %.2f us\n", fpga_us);
    printf("Equivalent to approxiamtely %.0f FPGA clock periods at %.3f MHz\n", fpga_us * FPGA_CLK_MHZ, FPGA_CLK_MHZ);
    if (fpga_us > 0.0)
    {
        printf("CPU / FPGA latency ratio: %.2fx\n", cpu_us / fpga_us);
    }
    return pass;
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

    double A[8][8];
    double B[8][8];
    int all_pass = 1;

    // Test 1: Original positive-only matrix test case
    for (int i = 0; i < 8; i++)
    {
        for (int j = 0; j < 8; j++)
        {
            A[i][j] = (i + j) % 8 + 1;
            B[i][j] = ((i * 2 + j) % 8) + 1;
        }
    }

    if (!run_test("Positive integers", regs, A, B))
    {
        all_pass = 0;
    }

    // Test 2: Signed integer matrices
    for (int i = 0; i < 8; i++)
    {
        for (int j = 0; j < 8; j++)
        {
            A[i][j] = (i + j) % 8 + 1;
            if ((i + j) % 2 == 1)
            {
                A[i][j] = -A[i][j]; // Make some elements negative
            }

            B[i][j] = ((i * 2 + j) % 8) + 1;
            if ((i + j) % 3 == 0)
            {
                B[i][j] = -B[i][j]; // Make some elements negative
            }
        }
    }

    if (!run_test("Signed integers", regs, A, B))
    {
        all_pass = 0;
    }

    // Test 3: Fractional signed Q8.8 matrices.
    for (int i = 0; i < 8; i++) {
        for (int j = 0; j < 8; j++)
        {
            A[i][j] = ((i + j) % 4 + 1) * .5; // Values like 0.5, 1.0, 1.5, 2.0
            if ((i + j) % 2 == 1)
            {
                A[i][j] = -A[i][j]; // Make some elements negative
            }

            B[i][j] = ((i * 2 + j) % 4 + 1) * .25; // Values like 0.25, 0.5, 0.75, 1.0
            if ((i + j) % 3 == 0)
            {
                B[i][j] = -B[i][j]; // Make some elements negative
            }
        }
    }

    if (!run_test("Fractional signed Q8.8", regs, A, B))
    {
        all_pass = 0;
    }


    // Test summary
    printf("\n==========================================\n");
    if (all_pass)
    {
        printf("All tests passed!\n");
    }
    else
    {
        printf("Some tests failed.\n");
    }

    printf("==========================================\n");

    // Deassert the control register to return to IDLE state
    regs[REG_CONTROL_STATUS] = 0;
    munmap((void *)regs, SPAN);
    close(fd);
    return all_pass ? 0 : 1;
}
