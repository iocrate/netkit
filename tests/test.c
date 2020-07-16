
int x;
int y;
int r;

void f() {
  x = y;
  asm volatile("": : : "memory");
  r = 1;
}