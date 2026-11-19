// Sanitizer canary: a data race that ThreadSanitizer must report ("WARNING: ThreadSanitizer: data
// race"): two threads increment a plain int without synchronization.
#include <thread>

static int counter;

static void work()
{
    for (int i = 0; i < 100000; ++i)
        ++counter;
}

int main()
{
    std::thread a(work);
    std::thread b(work);
    a.join();
    b.join();
    return counter > 0 ? 0 : 1;
}
