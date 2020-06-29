#include <iostream>
#include <thread>

void cb() {
  std::cout<<"Hello World\n";
}

class Runable {
public:
  std::string name = "abc";

  Runable(std::string name) {
    this->name = name;
  }

  void operator()() const {
    std::cout<<"Hello World,"<< this->name <<"\n";
  }
};

struct Runable2 {
  std::string name = "abc";

  Runable2(std::string name) {
    this->name = name;
  }

  void operator()(int n, std::string name2) const {
    std::cout<<"Hello World, "<< this->name << " " << n << " " << name2 <<"\n";
  }
};


int main() {
  Runable2 r("ABC");
  std::string name2 = "...";
  std::thread thr(r, 100, name2);
  thr.join();

  char *a = (char *) malloc(sizeof(char) * 8);
  *a = 'a';
  *(a + sizeof(char)) = 'b';
  std::cout<< *a << "\n";
  char *b = a;
  free(a);
  a = NULL;
  std::cout<< *b << "\n";

  return 0;
}