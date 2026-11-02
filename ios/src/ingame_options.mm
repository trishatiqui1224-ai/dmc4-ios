// Devil May Cry 4 iOS Port - In-Game Options Modal

#import <UIKit/UIKit.h>

#include <rex/logging.h>

#include "ingame_options.h"
#include "touch_controls.h"

namespace dmc4::ui {

void PresentInGameOptions(UIViewController* parentVC) {
    if (!parentVC) return;

    UIAlertController* alert = [UIAlertController alertControllerWithTitle:@"DEVIL MAY CRY 4"
                                                                   message:@"In-Game Combat & System Settings"
                                                            preferredStyle:UIAlertControllerStyleActionSheet];

    [alert addAction:[UIAlertAction actionWithTitle:@"Toggle Touch Controls"
                                              style:UIAlertActionStyleDefault
                                            handler:^(UIAlertAction* _Nonnull action) {
        dmc4::touch::SetOverlayVisible(!dmc4::touch::IsOverlayVisible());
    }]];

    [alert addAction:[UIAlertAction actionWithTitle:@"Dismiss" style:UIAlertActionStyleCancel handler:nil]];

    alert.popoverPresentationController.sourceView = parentVC.view;
    alert.popoverPresentationController.sourceRect = CGRectMake(parentVC.view.bounds.size.width / 2, parentVC.view.bounds.size.height / 2, 1, 1);
    [parentVC presentViewController:alert animated:YES completion:nil];
}

} // namespace dmc4::ui
