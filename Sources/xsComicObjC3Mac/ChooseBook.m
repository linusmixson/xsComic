#import <AppKit/AppKit.h>
#include <stdio.h>
#include <string.h>

int main(int argc, char *argv[]) {
    @autoreleasepool {
        [NSApplication sharedApplication];
        [NSApp setActivationPolicy:NSApplicationActivationPolicyAccessory];
        NSOpenPanel *panel = [NSOpenPanel openPanel];
        panel.title = @"Open Comic Book";
        panel.canChooseFiles = YES;
        panel.canChooseDirectories = YES;
        panel.allowsMultipleSelection = NO;
        if (argc == 2 && strcmp(argv[1], "--check") == 0) {
            return panel.canChooseFiles && panel.canChooseDirectories &&
                   !panel.allowsMultipleSelection ? 0 : 1;
        }
        if (argc != 1) return 2;
        [NSApp activate];
        if ([panel runModal] != NSModalResponseOK) return 1;
        const char *path = panel.URL.fileSystemRepresentation;
        return path && printf("%s\n", path) > 0 && fflush(stdout) == 0 ? 0 : 1;
    }
}
