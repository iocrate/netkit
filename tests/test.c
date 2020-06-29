#include <stdio.h>

int main(char * args, int argv) {
  volatile int *a = (int *) 0x1234;
  
  do {
    int b = 1;
    a = &b;
  } while (*a == 0);

  printf("%p", a);
  return 0;
}


