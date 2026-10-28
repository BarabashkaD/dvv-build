// wx include first, as in rawreel's GUI sources (design R11).
#include <wx/wx.h>

#include <wx/image.h>
#include <wx/init.h>

#include <cstdio>

int main(int argc, char** argv) {
    wxInitializer initializer(argc, argv);  // console initialisation: no display needed
    if (!initializer.IsOk()) {
        std::fputs("wxInitializer failed\n", stderr);
        return 1;
    }
    // "Grüße": UTF-8 in, UTF-8 out.
    const wxString text = wxString::FromUTF8("Gr\xC3\xBC\xC3\x9F" "e");
    if (text.length() != 5 || text.utf8_string() != "Gr\xC3\xBC\xC3\x9F" "e") {
        return 2;
    }
    wxImage image(4, 2);  // references wxcore, so its link dependencies are real (design R3)
    image.SetRGB(1, 1, 10, 20, 30);
    if (!image.IsOk() || image.GetGreen(1, 1) != 20) {
        return 3;
    }
    std::puts("wx consumer ok");
    return 0;
}
