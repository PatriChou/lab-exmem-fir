#include "fir.h"

void __attribute__ ( ( section ( ".mprjram" ) ) ) initfir() {
	//initial your fir
	int i;

	for(i=0; i<N; i++){
		inputbuffer[i] 	= 0;
		outputsignal[i] = 0;
	}
}

int* __attribute__ ( ( section ( ".mprjram" ) ) ) fir(){
	initfir();
	//write down your fir
	int i, j;

	for(i=0; i<N; i++){
		for(j=0; j<=i; j++){
			outputsignal[i] = outputsignal[i] + inputsignal[i-j] * taps[j];
		}
	}

	return outputsignal;
}
		
