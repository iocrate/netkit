
// int x;
// int y;
// int r;

// void f() {
//   x = y;
//   asm volatile("": : : "memory");
//   r = 1;
// }

#include <stdio.h>
#include <unistd.h>
#include <sys/eventfd.h>

int main(char* args, int argv) {
  long a = 1;
  long b = (long)(&a);
  long fd = eventfd(0, 0);
  write(fd, &b, 8);
  a = 2;
  long c = 3;
  read(fd, &c, 8);
  long *d = (long *)(c);
  printf("d = %ld", *d);
  return 0;
}