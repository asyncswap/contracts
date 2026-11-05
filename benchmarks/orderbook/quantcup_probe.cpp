// Comparison probe; links the unmodified ajtulloch/quantcup-orderbook core.
// Captures execution prices absent from its same-price-only bundled examples.
#include <stddef.h>
#include "engine.h"
#include <cstdlib>
#include <iostream>
#include <vector>

static std::vector<t_execution> fills;
void execution(t_execution fill) { fills.push_back(fill); }

static void check(bool condition, const char* message) {
    if (!condition) {
        std::cerr << message << '\n';
        std::exit(1);
    }
}

int main() {
    init();
    limit(t_order{"ABC", "SEL", 1, 100, 10});
    limit(t_order{"ABC", "BUY", 0, 110, 10});
    check(fills.size() == 2, "buy cross must emit both sides");
    check(fills[0].price == 110 && fills[1].price == 110,
          "this snapshot executes at incoming buy price");
    std::cout << "resting ask 100, incoming bid 110: execution " << fills[0].price << '\n';
    destroy();

    init();
    fills.clear();
    limit(t_order{"ABC", "BUY", 0, 100, 10});
    limit(t_order{"ABC", "SEL", 1, 90, 10});
    check(fills.size() == 2, "sell cross must emit both sides");
    check(fills[0].price == 90 && fills[1].price == 90,
          "this snapshot executes at incoming sell price");
    std::cout << "resting bid 100, incoming ask 90: execution " << fills[0].price << '\n';
    destroy();
}
