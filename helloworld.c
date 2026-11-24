#include <stdio.h>
#include <stdint.h>
#include "xil_printf.h"
#include "xil_io.h"
#include "sleep.h"

/* AXI base addresses */
#define MULT_BASE_ADDR  0x43C00000
#define BRAM_BASE_ADDR  0x40000000
#define FIFO_BASE_ADDR  0x43C10000

/* Multiplier registers */
#define A_REG_ADDR      (MULT_BASE_ADDR + 0x00)
#define B_REG_ADDR      (MULT_BASE_ADDR + 0x04)
#define P_REG_ADDR      (MULT_BASE_ADDR + 0x08)

/* FIFO registers */
#define FIFO_REV        (FIFO_BASE_ADDR + 0x00)
#define FIFO_RESET      (FIFO_BASE_ADDR + 0x04)
#define FIFO_WR_DATA    (FIFO_BASE_ADDR + 0x08)
#define FIFO_RD_REQ     (FIFO_BASE_ADDR + 0x0C)
#define FIFO_RD_DATA    (FIFO_BASE_ADDR + 0x10)
#define FIFO_STATUS     (FIFO_BASE_ADDR + 0x14)
#define FIFO_COUNT      (FIFO_BASE_ADDR + 0x18)
#define FIFO_CONFIG     (FIFO_BASE_ADDR + 0x1C)
#define FIFO_THRESH     (FIFO_BASE_ADDR + 0x20)

/* FIFO status bits */
#define FIFO_EMPTY      0x01
#define FIFO_FULL       0x02
#define FIFO_AEMPTY     0x04
#define FIFO_AFULL      0x08
#define FIFO_RD_VALID   0x10

int main()
{
    int k;
    int timeout;
    uint32_t product;
    uint32_t value;
    uint32_t status;



    xil_printf("\r\nMichael Hernandez - Lab 4\r\n");
    xil_printf("Multiplier, BRAM, and AXI FIFO Test\r\n\r\n");

    /*
     * TEST 1: FIFO reset and configuration registers
     */
    xil_printf("TEST 1: FIFO reset and configuration\r\n");

    Xil_Out32(FIFO_RESET, 1);
    usleep(10);

    xil_printf("FIFO Revision  = 0x%08X\r\n", Xil_In32(FIFO_REV));
    xil_printf("FIFO Config    = 0x%08X\r\n", Xil_In32(FIFO_CONFIG));
    xil_printf("FIFO Threshold = 0x%08X\r\n", Xil_In32(FIFO_THRESH));
    xil_printf("FIFO Status    = 0x%08X\r\n", Xil_In32(FIFO_STATUS));
    xil_printf("FIFO Count     = %d\r\n\r\n", Xil_In32(FIFO_COUNT));

    /*
     * TEST 2: Write data into FIFO and read it back
     */
    xil_printf("TEST 2: FIFO write and read ordering\r\n");

    Xil_Out32(FIFO_WR_DATA, 11);
    Xil_Out32(FIFO_WR_DATA, 22);
    Xil_Out32(FIFO_WR_DATA, 33);
    Xil_Out32(FIFO_WR_DATA, 44);

    xil_printf("FIFO Count after writes = %d\r\n", Xil_In32(FIFO_COUNT));

    for (k = 0; k < 4; k = k + 1) {
        Xil_Out32(FIFO_RD_REQ, 1);

        timeout = 0;
        do {
            status = Xil_In32(FIFO_STATUS);
            timeout = timeout + 1;
        } while (((status & FIFO_RD_VALID) == 0) && (timeout < 1000));

        if (timeout < 1000) {
            value = Xil_In32(FIFO_RD_DATA);
            xil_printf("FIFO Read %d = %d\r\n", k + 1, value);
        }
        else {
            xil_printf("FIFO read timeout\r\n");
        }
    }

    xil_printf("FIFO Count after reads = %d\r\n\r\n",
               Xil_In32(FIFO_COUNT));

    /*
     * TEST 3: FIFO full condition
     */
    xil_printf("TEST 3: FIFO full condition\r\n");

    Xil_Out32(FIFO_RESET, 1);
    usleep(10);

    for (k = 0; k < 32; k = k + 1) {
        Xil_Out32(FIFO_WR_DATA, k + 1);
    }

    status = Xil_In32(FIFO_STATUS);

    xil_printf("FIFO Count = %d\r\n", Xil_In32(FIFO_COUNT));
    xil_printf("FIFO Status = 0x%08X\r\n", status);

    if ((status & FIFO_FULL) != 0) {
        xil_printf("FIFO full flag is asserted\r\n");
    }

    Xil_Out32(FIFO_WR_DATA, 999);
    xil_printf("Extra write attempted while FIFO was full\r\n");
    xil_printf("FIFO Count = %d\r\n\r\n", Xil_In32(FIFO_COUNT));

    /*
     * TEST 4: FIFO software reset
     */
    xil_printf("TEST 4: FIFO software reset\r\n");

    Xil_Out32(FIFO_RESET, 1);
    usleep(10);

    status = Xil_In32(FIFO_STATUS);

    xil_printf("FIFO Count after reset = %d\r\n", Xil_In32(FIFO_COUNT));
    xil_printf("FIFO Status after reset = 0x%08X\r\n", status);

    /*
     * TEST 5: Multiplier results stored in BRAM
     */
    xil_printf("\r\nTEST 5: Multiplier and BRAM\r\n");

    for (k = 0; k < 32; k = k + 1) {
        Xil_Out32(A_REG_ADDR, k + 1);
        Xil_Out32(B_REG_ADDR, k + 1);

        usleep(1);

        product = Xil_In32(P_REG_ADDR);

        Xil_Out32(BRAM_BASE_ADDR + (k * 4), product);

        xil_printf("%d x %d = %d\r\n",
                   k + 1, k + 1, product);
    }

    xil_printf("\r\nReading BRAM contents\r\n");

    for (k = 0; k < 32; k = k + 1) {
        value = Xil_In32(BRAM_BASE_ADDR + (k * 4));

        xil_printf("BRAM[%d] = %d\r\n", k, value);
    }

    xil_printf("\r\nALL SOFTWARE TESTS COMPLETE\r\n");


    return 0;
}
