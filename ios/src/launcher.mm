// Devil May Cry 4 (Title ID: 434307DF) - Modern iOS Launcher & Configurator
// Capcom MT Framework 1.4 | MoltenVK Metal3 | ProMotion 120Hz

#import <UIKit/UIKit.h>

#include <SDL3/SDL.h>

#include <filesystem>
#include <fstream>
#include <string>
#include <vector>

#include <rex/cvar.h>
#include <rex/logging.h>

#include "battery.h"
#include "display_rate.h"
#include "dmc4_app.h"
#include "launcher.h"
#include "probe.h"
#include "touch_controls.h"

namespace fs = std::filesystem;

// ---------------------------------------------------------------------------
//  Launcher View Controller
// ---------------------------------------------------------------------------

@interface DMC4LauncherViewController : UIViewController {
    fs::path _documents;
    fs::path _selectedGame;
    std::vector<std::string> _args;

    UILabel* _titleLabel;
    UILabel* _subtitleLabel;
    UILabel* _gameStatusLabel;
    UISegmentedControl* _presetSegment;
    UISegmentedControl* _fpsSegment;
    UISwitch* _casSwitch;
    UISwitch* _touchSwitch;
    UIButton* _btnLaunch;
}

- (instancetype)initWithDocuments:(const fs::path&)docs
                         gamePath:(const fs::path&)game
                             args:(const std::vector<std::string>&)args;
@end

@implementation DMC4LauncherViewController

- (instancetype)initWithDocuments:(const fs::path&)docs
                         gamePath:(const fs::path&)game
                             args:(const std::vector<std::string>&)args {
    if (self = [super init]) {
        _documents = docs;
        _selectedGame = game;
        _args = args;
    }
    return self;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.view.backgroundColor = [UIColor colorWithRed:0.04f green:0.05f blue:0.08f alpha:1.0f];

    CGSize sz = self.view.bounds.size;
    CGFloat cx = sz.width / 2.0f;

    // Header Title
    _titleLabel = [[UILabel alloc] initWithFrame:CGRectMake(40, 30, sz.width - 80, 40)];
    _titleLabel.text = @"DEVIL MAY CRY 4";
    _titleLabel.textColor = [UIColor colorWithRed:0.95f green:0.15f blue:0.25f alpha:1.0f];
    _titleLabel.font = [UIFont systemFontOfSize:28.0f weight:UIFontWeightBlack];
    _titleLabel.textAlignment = NSTextAlignmentCenter;
    [self.view addSubview:_titleLabel];

    _subtitleLabel = [[UILabel alloc] initWithFrame:CGRectMake(40, 70, sz.width - 80, 22)];
    _subtitleLabel.text = @"Capcom MT Framework 1.4 | MoltenVK Metal3 | Title ID: 434307DF";
    _subtitleLabel.textColor = [UIColor colorWithRed:0.0f green:0.85f blue:1.0f alpha:0.9f];
    _subtitleLabel.font = [UIFont systemFontOfSize:12.0f weight:UIFontWeightSemibold];
    _subtitleLabel.textAlignment = NSTextAlignmentCenter;
    [self.view addSubview:_subtitleLabel];

    // Game Path Status
    _gameStatusLabel = [[UILabel alloc] initWithFrame:CGRectMake(40, 105, sz.width - 80, 30)];
    if (!_selectedGame.empty()) {
        _gameStatusLabel.text = [NSString stringWithFormat:@"Game: %@", [NSString stringWithUTF8String:_selectedGame.filename().string().c_str()]];
        _gameStatusLabel.textColor = [UIColor colorWithRed:0.2f green:0.9f blue:0.4f alpha:1.0f];
    } else {
        _gameStatusLabel.text = @"No ISO found in Documents/! Place DMC4 ISO or game/ folder.";
        _gameStatusLabel.textColor = [UIColor colorWithRed:1.0f green:0.4f blue:0.4f alpha:1.0f];
    }
    _gameStatusLabel.font = [UIFont systemFontOfSize:13.0f weight:UIFontWeightMedium];
    _gameStatusLabel.textAlignment = NSTextAlignmentCenter;
    [self.view addSubview:_gameStatusLabel];

    // Presets Control (720p Battery, 900p Balanced, 1080p Crisp HD, Native Retina)
    UILabel* presetLabel = [[UILabel alloc] initWithFrame:CGRectMake(60, 150, 180, 24)];
    presetLabel.text = @"Display Quality Preset:";
    presetLabel.textColor = [UIColor whiteColor];
    presetLabel.font = [UIFont systemFontOfSize:14.0f weight:UIFontWeightBold];
    [self.view addSubview:presetLabel];

    _presetSegment = [[UISegmentedControl alloc] initWithItems:@[@"720p Battery", @"900p", @"1080p Crisp", @"Native Retina"]];
    _presetSegment.frame = CGRectMake(60, 180, sz.width - 120, 36);
    _presetSegment.selectedSegmentIndex = 2; // Default 1080p Crisp HD
    [self.view addSubview:_presetSegment];

    // Framerate (30 Hz, 60 Hz, 120 Hz ProMotion)
    UILabel* fpsLabel = [[UILabel alloc] initWithFrame:CGRectMake(60, 230, 180, 24)];
    fpsLabel.text = @"ProMotion Framerate:";
    fpsLabel.textColor = [UIColor whiteColor];
    fpsLabel.font = [UIFont systemFontOfSize:14.0f weight:UIFontWeightBold];
    [self.view addSubview:fpsLabel];

    _fpsSegment = [[UISegmentedControl alloc] initWithItems:@[@"30 Hz", @"60 Hz", @"120 Hz (ProMotion)"]];
    _fpsSegment.frame = CGRectMake(60, 260, sz.width - 120, 36);
    _fpsSegment.selectedSegmentIndex = 1; // Default 60 FPS
    [self.view addSubview:_fpsSegment];

    // Launch Button
    _btnLaunch = [UIButton buttonWithType:UIButtonTypeCustom];
    _btnLaunch.frame = CGRectMake(cx - 140, sz.height - 75, 280, 52);
    _btnLaunch.backgroundColor = [UIColor colorWithRed:0.9f green:0.15f blue:0.25f alpha:1.0f];
    _btnLaunch.layer.cornerRadius = 26.0f;
    _btnLaunch.layer.borderColor = [UIColor whiteColor].CGColor;
    _btnLaunch.layer.borderWidth = 2.0f;
    [_btnLaunch setTitle:@"ENTER COMBAT" forState:UIControlStateNormal];
    [_btnLaunch setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
    _btnLaunch.titleLabel.font = [UIFont systemFontOfSize:16.0f weight:UIFontWeightHeavy];
    [_btnLaunch addTarget:self action:@selector(onLaunchTapped) forControlEvents:UIControlEventTouchUpInside];
    [self.view addSubview:_btnLaunch];
}

- (void)onLaunchTapped {
    REXLOG_INFO("[DMC4 Launcher] User selected 'ENTER COMBAT'. Starting MT Framework engine...");

    // Apply selected presets to runtime args
    switch (_presetSegment.selectedSegmentIndex) {
        case 0: // 720p Battery
            _args.push_back("--resolution_scale=1");
            _args.push_back("--anisotropic_override=8");
            break;
        case 1: // 900p
            _args.push_back("--resolution_scale=1");
            _args.push_back("--anisotropic_override=16");
            break;
        case 2: // 1080p Crisp HD
            _args.push_back("--resolution_scale=1");
            _args.push_back("--anisotropic_override=16");
            _args.push_back("--ios_metalfx_upscaling=true");
            break;
        case 3: // Native Retina
            _args.push_back("--resolution_scale=1");
            _args.push_back("--anisotropic_override=16");
            _args.push_back("--ios_metalfx_upscaling=true");
            break;
    }

    int target_fps = 60;
    if (_fpsSegment.selectedSegmentIndex == 0) target_fps = 30;
    else if (_fpsSegment.selectedSegmentIndex == 2) target_fps = 120;
    _args.push_back(std::string("--ios_target_fps=") + std::to_string(target_fps));

    [self dismissViewControllerAnimated:YES completion:^{
        // Enter game application
        dmc4::app::RunGame(_args, _selectedGame);
    }];
}

@end

// ---------------------------------------------------------------------------
//  Launcher Public API
// ---------------------------------------------------------------------------

namespace dmc4::launcher {

fs::path Documents() {
    NSArray<NSString*>* paths = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES);
    return fs::path(paths.firstObject.UTF8String);
}

std::vector<fs::path> FindGameFiles(const fs::path& documents) {
    std::vector<fs::path> result;
    std::error_code ec;
    if (fs::exists(documents / "game", ec)) {
        result.push_back(documents / "game");
    }
    for (const auto& entry : fs::directory_iterator(documents, ec)) {
        if (entry.is_regular_file() && entry.path().extension() == ".iso") {
            result.push_back(entry.path());
        }
    }
    return result;
}

void ShowLauncher(int argc, char* argv[], std::vector<std::string>& game_args, const fs::path& game_path) {
    UIWindow* keyWindow = nil;
    for (UIScene* scene in [UIApplication sharedApplication].connectedScenes) {
        if ([scene isKindOfClass:[UIWindowScene class]]) {
            UIWindowScene* ws = (UIWindowScene*)scene;
            for (UIWindow* w in ws.windows) {
                if (w.isKeyWindow) {
                    keyWindow = w;
                    break;
                }
            }
            if (!keyWindow && ws.windows.count > 0) {
                keyWindow = ws.windows.firstObject;
            }
        }
        if (keyWindow) break;
    }

    UIViewController* rootVC = keyWindow.rootViewController;
    if (rootVC) {
        DMC4LauncherViewController* launcherVC =
            [[DMC4LauncherViewController alloc] initWithDocuments:Documents()
                                                         gamePath:game_path
                                                             args:game_args];
        launcherVC.modalPresentationStyle = UIModalPresentationFullScreen;
        [rootVC presentViewController:launcherVC animated:NO completion:nil];
    } else {
        // Fallback: direct launch if UIKit view controller hierarchy is not yet populated
        dmc4::app::RunGame(game_args, game_path);
    }
}

std::vector<std::string> GetConfiguredArguments(const fs::path& documents) {
    return {};
}

} // namespace dmc4::launcher
