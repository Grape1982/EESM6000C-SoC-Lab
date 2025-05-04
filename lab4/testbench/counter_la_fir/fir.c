#include "fir.h"
#include <stdint.h>

// hardware register
#define reg_fir_control  (*(volatile uint32_t*)0x30000000)
#define reg_fir_length   (*(volatile uint32_t*)0x30000010)
#define reg_fir_coeff(i) (*(volatile uint32_t*)(0x30000080 + (i << 2)))
#define reg_fir_x        (*(volatile uint32_t*)0x30000040)
#define reg_fir_y        (*(volatile uint32_t*)0x30000044)

void init_fir() {
    reg_fir_length = N;
    
    // load coefficient
    for (uint32_t i = 0; i < N; i++) {
        reg_fir_coeff(i) = taps[i];
    }
}

int* fir() {
    init_fir();
    
    reg_fir_control = 0x00000001;
    
    reg_fir_x = inputsignal[0];  
    reg_fir_x = inputsignal[1]; 
    
    for (uint32_t i = 2; i < N; i++) {
        outputsignal[i-2] = reg_fir_y;   
        reg_fir_x = inputsignal[i];    
    }
    

    outputsignal[N-2] = reg_fir_y;
    outputsignal[N-1] = reg_fir_y;

    return outputsignal;
}




