// Sanitizer canary: a leak that LeakSanitizer must report ("detected memory leaks", non-zero exit).
// The volatile sink keeps the allocation from being optimized away; overwriting it drops the last
// reference.
#include <cstdlib>

static void* volatile sink;

int main()
{
    sink = std::malloc(64);
    sink = nullptr;
    return 0;
}
