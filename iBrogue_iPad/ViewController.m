//
//  ViewController.m
//  iBrogue_iPad
//
//  Created by Seth Howard on 2/22/13.
//  Copyright (c) 2013 Seth howard. All rights reserved.
//

#import "ViewController.h"
#import "RogueDriver.h"
#import "Viewport.h"
#import "GameCenterManager.h"
#import "UIViewController+UIViewController_GCLeaderBoardView.h"
#import "AboutViewController.h"
#import "GameSettings.h"

#define kStationaryTime 0.25f
#define kGamePlayHitArea CGRectMake(209., 74., 810., 650.)     // seems to be a method in the c code that does this but didn't work as expected
#define kGameSideBarArea CGRectMake(0., 0., 210., 748.)
#define BROGUE_VERSION	4	// A special version number that's incremented only when
// something about the OS X high scores file structure changes.

Viewport *theMainDisplay;
ViewController *viewController;

typedef enum {
    KeyDownUp = 0,
    KeyDownRight,
    KeyDownDown,
    KeyDownLeft,
}KeyDown;

#define kESC_Key @"\033"

@interface ViewController () <UITextFieldDelegate, UIGestureRecognizerDelegate>
- (IBAction)escButtonPressed:(id)sender;
- (IBAction)upButtonPressed:(id)sender;
- (IBAction)downButtonPressed:(id)sender;
- (IBAction)rightButtonPressed:(id)sender;
- (IBAction)leftButtonPressed:(id)sender;
- (IBAction)upLeftButtonPressed:(id)sender;
- (IBAction)upRightButtonPressed:(id)sender;
- (IBAction)downLeftButtonPressed:(id)sender;
- (IBAction)downRightButtonPressed:(id)sender;
- (IBAction)seedKeyPressed:(id)sender;
- (IBAction)showLeaderBoardButtonPressed:(id)sender;
- (IBAction)aboutButtonPressed:(id)sender;
- (IBAction)showInventoryButtonPressed:(id)sender;
- (void)showInventoryOnDeathButton:(BOOL)show;

@property (weak, nonatomic) IBOutlet UIView *directionalButtonSubContainer;
@property (weak, nonatomic) IBOutlet UIButton *seedButton;
@property (weak, nonatomic) IBOutlet Viewport *secondaryDisplay;   // game etc
@property (nonatomic, strong) IBOutlet Viewport *titleDisplay;
@property (weak, nonatomic) IBOutlet UIView *buttonView;
@property (weak, nonatomic) IBOutlet UIButton *escButton;
@property (nonatomic, strong) NSMutableArray *cachedTouches; // collection of iBTouches
@property (weak, nonatomic) IBOutlet UIView *playerControlView;
@property (weak, nonatomic) IBOutlet UITextField *aTextField;
@property (nonatomic, strong) NSMutableArray *cachedKeyStrokes;
@property (weak, nonatomic) IBOutlet UIButton *showInventoryButton;
@property (weak, nonatomic) IBOutlet UILabel *seedLabel;

// gestures
@property (nonatomic, strong) UIPinchGestureRecognizer *directionalPinch;

@end

@implementation ViewController {
    @private
    __unused NSTimer __strong *_autoSaveTimer;
    CGPoint _lastTouchLocation;
    NSTimer __strong *_stationaryTouchTimer;
    BOOL _areDirectionalControlsHidden;
    // TODO: set this to ivars and dynamic set. Pressing in the left side of the screen in high scores does not register the touch 
    BOOL _isSideBarSingleTap;       // handles special touch cases when user touches the side bar
    BOOL _ishandlingDoubleTap;      // handles special double tap touch case
    BrogueGameEvent _lastBrogueGameEvent;
}
@dynamic cachedKeyStrokeCount;
@dynamic cachedTouchesCount;

- (void)viewDidLoad
{
    [super viewDidLoad];
    [GameCenterManager sharedInstance];
    [[GameCenterManager sharedInstance] authenticateLocalUser];
	// Do any additional setup after loading the view, typically from a nib.
    
    if (!theMainDisplay) {
        self.titleDisplay.hidden = YES;
        theMainDisplay = self.titleDisplay;
        viewController = self;
        _cachedTouches = [NSMutableArray arrayWithCapacity:1];
        _cachedKeyStrokes = [NSMutableArray arrayWithCapacity:1];
        
        [self addNotificationObservers];
        
        [self.buttonView setAlpha:0];
        
        double delayInSeconds = 2.0;
        dispatch_time_t popTime = dispatch_time(DISPATCH_TIME_NOW, (int64_t)(delayInSeconds * NSEC_PER_SEC));
        dispatch_after(popTime, dispatch_get_main_queue(), ^(void){
            [UIView animateWithDuration:0.2 animations:^{
                self.buttonView.alpha = 1.;
            }];
        });
        
        [self initGestureRecognizers];
    }
    
    [self becomeFirstResponder];
    [self playBrogue];
}

- (void)addNotificationObservers {
    NSNotificationCenter *center = [NSNotificationCenter defaultCenter];
    [center addObserver:self selector:@selector(didShowKeyboard) name:UIKeyboardDidShowNotification object:nil];
    [center addObserver:self selector:@selector(didHideKeyboard) name:UIKeyboardWillHideNotification object:nil];
    [center addObserver:self selector:@selector(applicationDidBecomeActive) name:UIApplicationDidBecomeActiveNotification object:nil];
}

- (void)applicationDidBecomeActive {
    [self.secondaryDisplay removeMagnifyingGlass];
}

- (void)didReceiveMemoryWarning
{
    [super didReceiveMemoryWarning];
    // Dispose of any resources that can be recreated.
}

- (void)awakeFromNib
{
    //	extern Viewport *theMainDisplay;
    //	CGSize theSize;
	short versionNumber;
    
	versionNumber = [[NSUserDefaults standardUserDefaults] integerForKey:@"Brogue version"];
	if (versionNumber == 0 || versionNumber < BROGUE_VERSION) {
		// This is so we know when to purge the relevant preferences and save them anew.
		[[NSUserDefaults standardUserDefaults] removeObjectForKey:@"NSWindow Frame Brogue main window"];
        
		if (versionNumber != 0) {
			[[NSUserDefaults standardUserDefaults] removeObjectForKey:@"Brogue version"];
		}
		[[NSUserDefaults standardUserDefaults] setInteger:BROGUE_VERSION forKey:@"Brogue version"];
		[[NSUserDefaults standardUserDefaults] synchronize];
	}
}

- (void)playBrogue
{
    rogueMain();
}

#pragma mark - Shake Motion

// Used for escape
- (BOOL)canBecomeFirstResponder {
    return YES;
}

- (void)motionBegan:(UIEventSubtype)motion withEvent:(UIEvent *)event{
    // you can do any thing at this stage what ever you want. Change the song in playlist, show photo, change photo or whatever you want to do
    
    if (![[GameSettings sharedInstance] allowShake]) {
        return;
    }
    
    @synchronized(self.cachedKeyStrokes) {
        [self.cachedKeyStrokes removeAllObjects];
        [self.cachedKeyStrokes addObject:kESC_Key];
    }
}

#pragma mark - touches

- (void)initGestureRecognizers {
    // IS slow as shit. Leaving the code in so no one ever gets the bright idea to create a double tap gesture
   // UITapGestureRecognizer *doubleTap = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(handleDoubleTap:)];
   // doubleTap.numberOfTapsRequired = 2;
   // doubleTap.delegate = self;
  //  [self.secondaryDisplay addGestureRecognizer:doubleTap];
    
    if ([[GameSettings sharedInstance] allowPinchToZoomDirectional]) {
        [self turnOnPinchGesture];
    }
}

// Pinch to hide the directional controls

- (void)turnOnPinchGesture {
    if (!self.directionalPinch) {
        self.directionalPinch = [[UIPinchGestureRecognizer alloc] initWithTarget:self action:@selector(handlePinch:)];
        [self.playerControlView addGestureRecognizer:self.directionalPinch];
    }
}

- (void)turnOffPinchGesture {
    if (self.directionalPinch) {
        [self.playerControlView removeGestureRecognizer:self.directionalPinch];
        self.directionalPinch = nil;
    }
}

- (void)handlePinch:(UIPinchGestureRecognizer *)pinch {
    if (pinch.velocity < 0 && !_areDirectionalControlsHidden) {
        self.directionalButtonSubContainer.transform = CGAffineTransformMakeScale(pinch.scale, pinch.scale);
    }
    else if(pinch.velocity > 0 && _areDirectionalControlsHidden){
        self.directionalButtonSubContainer.transform = CGAffineTransformMakeScale(1 - pinch.scale, 1 - pinch.scale);
    }
    
    if (pinch.state == UIGestureRecognizerStateEnded || pinch.state == UIGestureRecognizerStateCancelled) {
        if (pinch.scale < 0.6f) {
            [UIView animateWithDuration:0.2 animations:^{
                self.directionalButtonSubContainer.transform = CGAffineTransformMakeScale(.0000001, .0000001);
            }];
            
            _areDirectionalControlsHidden = YES;
        }
        else {
            [UIView animateWithDuration:0.2 animations:^{
                self.directionalButtonSubContainer.transform = CGAffineTransformMakeScale(1., 1.);
            }];
            
            _areDirectionalControlsHidden = NO;
        }
    }
}

- (BOOL)gestureRecognizer:(UIGestureRecognizer *)gestureRecognizer shouldReceiveTouch:(UITouch *)touch {
    CGPoint pointInView = [touch locationInView:gestureRecognizer.view];
    
    if ( [gestureRecognizer isMemberOfClass:[UITapGestureRecognizer class]]
        && CGRectContainsPoint(self.playerControlView.frame, pointInView)) {
        return NO;
    }
    
    return YES;
}

// TODO: touches are manually cached here instead of going through a central point
// we save the last touch point so the second tap doesn't stray to far from the first tap. Otherwise the user's expectations of where they want to go and where they go might not match up
- (void)handleDoubleTap:(UITapGestureRecognizer *)tap {
    [self stopStationaryTouchTimer];
    [self.secondaryDisplay removeMagnifyingGlass];
    
    @synchronized(self.cachedTouches) {
        // we double tapped... send along another mouse down and up to the game
        iBTouch touchDown;
        touchDown.phase = UITouchPhaseStationary;
        touchDown.location = _lastTouchLocation;
        
        [self.cachedTouches addObject:[NSValue value:&touchDown withObjCType:@encode(iBTouch)]];
        
        iBTouch touchMoved;
        touchMoved.phase = UITouchPhaseMoved;
        touchMoved.location = _lastTouchLocation;
        [self.cachedTouches addObject:[NSValue value:&touchMoved withObjCType:@encode(iBTouch)]];
        
        iBTouch touchUp;
        touchUp.phase = UITouchPhaseEnded;
        touchUp.location = _lastTouchLocation;
        
        [self.cachedTouches addObject:[NSValue value:&touchUp withObjCType:@encode(iBTouch)]];
    }
}

- (void)addTouchToCache:(UITouch *)touch {
    @synchronized(self.cachedTouches){
        iBTouch ibtouch;
        ibtouch.phase = touch.phase;
        
        // we need to make sure that a phase end touch ends in the same spot as the previous touch or a borks the char movement
        if (touch.phase == UITouchPhaseEnded) {
            ibtouch.location = _lastTouchLocation;
        }
        else {
          ibtouch.location = [touch locationInView:theMainDisplay];  
        }
        
       // NSLog(@"##### %i", touch.phase);
        
        _lastTouchLocation = ibtouch.location;
        [self.cachedTouches addObject:[NSValue value:&ibtouch withObjCType:@encode(iBTouch)]];
    }
}

- (iBTouch)getTouchAtIndex:(uint)index {
    NSValue *anObj = [self.cachedTouches objectAtIndex:index];
    iBTouch touch;
    [anObj getValue:&touch];
    
    return touch;
}

- (void)removeTouchAtIndex:(uint)index {
    @synchronized(self.cachedTouches){
        if ([self.cachedTouches count] > 0) {
            [self.cachedTouches removeObjectAtIndex:index];
        }
    }
}

- (uint)cachedTouchesCount {
    return [self.cachedTouches count];
}

- (void)handleStationary:(NSTimer *)timer {
    if (self.secondaryDisplay.hidden == NO && !self.blockMagView) {
        NSValue *v = timer.userInfo;
        CGPoint point = [v CGPointValue];
        
        dispatch_async(dispatch_get_main_queue(), ^{
            [self.secondaryDisplay addMagnifyingGlassAtPoint:point];
        });
    }
    
    [self stopStationaryTouchTimer];
}

- (void)escapeTouchKeyEvent {
    @synchronized(self.cachedKeyStrokes){
        [self.cachedKeyStrokes removeAllObjects];
        [self.cachedKeyStrokes addObject:kESC_Key];
    }
    
    @synchronized(self.cachedTouches) {
                [self.cachedTouches removeAllObjects];
    }
}

- (void)touchesBegan:(NSSet *)touches withEvent:(UIEvent *)event {
   // NSLog(@"%s", __PRETTY_FUNCTION__);
     _isSideBarSingleTap = NO;

    [touches enumerateObjectsUsingBlock:^(UITouch *touch, BOOL *stop) {
        CGPoint touchPoint = [touch locationInView:theMainDisplay];
        
        if (touch.tapCount == 2) {
            // if we're in the game we just want to send our custom double tap and return
            if ([self isPointInGamePlayArea:touchPoint]) {
                //This will cancel the singleTap action
                [self handleDoubleTap:nil];
                return ;
            }
            else {
                // we're outside the play area. (most likely the side bar). This handles that side bar case where do don't actually send a touch up until the user has double tapped
                @synchronized(self.cachedTouches) {
                    iBTouch touchUp;
                    touchUp.phase = UITouchPhaseEnded;
#warning _lastTouchLocation is set in [self addTouchToCach:]. Not what I'd call intuitive and potentially deal breaking if changes were made
                    touchUp.location = _lastTouchLocation;
                    
                    [self.cachedTouches addObject:[NSValue value:&touchUp withObjCType:@encode(iBTouch)]];
                    
                    _ishandlingDoubleTap = YES;
                }
            }
        }
        // no tap just a touch
        else {
            // if we touch in the side bar we want to block the touches up and so we set a bool here to do just that. This forces the user to double tap anything in the side bar that they actually want to run to and allows a single tap to bring up the selection information.
            // when a user touches the screen we need to 'nudge' the movement so brogue event handles can update (highlight, show popup, etc) where we touched
            if (CGRectContainsPoint(kGameSideBarArea, touchPoint) && _lastBrogueGameEvent != BrogueGameEventShowHighScores) {
        //        [self escapeTouchKeyEvent];
                
                @synchronized(self.cachedTouches) {
                    iBTouch touchMoved;
                    touchMoved.phase = UITouchPhaseMoved;
                    touchMoved.location = touchPoint;
                    [self.cachedTouches addObject:[NSValue value:&touchMoved withObjCType:@encode(iBTouch)]];
                }
                
                _isSideBarSingleTap = YES;
            }
            
            // Get a single touch and it's location
            [self addTouchToCache:touch];
            [self startStationaryTouchTimerWithTouch:touch andTimeout:kStationaryTime];
        }
    }];
}

- (void)touchesMoved:(NSSet *)touches withEvent:(UIEvent *)event {
 //   NSLog(@" ##### %@", touches);
    [touches enumerateObjectsUsingBlock:^(UITouch *touch, BOOL *stop) {
        // Get a single touch and it's location
        [self addTouchToCache:touch];
        [self startStationaryTouchTimerWithTouch:touch andTimeout:kStationaryTime];
    }];
}

- (void)touchesEnded:(NSSet *)touches withEvent:(UIEvent *)event {
  //  NSLog(@"%s %i", __PRETTY_FUNCTION__, _ishandlingDoubleTap);
    [self stopStationaryTouchTimer];
    
    // under certain conditions we don't actually want to pass through a 'mouse up'
    if (!_ishandlingDoubleTap && !_isSideBarSingleTap) {
        [touches enumerateObjectsUsingBlock:^(UITouch *touch, BOOL *stop) {
            // Get a single touch and it's location
            [self addTouchToCache:touch];
        }];
    }

    _ishandlingDoubleTap = NO;
}

#pragma mark - Magnifier

- (void)stopStationaryTouchTimer {
    [_stationaryTouchTimer invalidate];
    _stationaryTouchTimer = nil;
}

- (void)startStationaryTouchTimerWithTouch:(UITouch *)touch andTimeout:(NSTimeInterval)timeOut {
    if ([[GameSettings sharedInstance] allowMagnifier]) {
        [self stopStationaryTouchTimer];
        
        if ([self isPointInGamePlayArea:[touch locationInView:self.secondaryDisplay]]) {
            _stationaryTouchTimer = [NSTimer scheduledTimerWithTimeInterval:timeOut target:self selector:@selector(handleStationary:) userInfo:[NSValue valueWithCGPoint:[touch locationInView:self.secondaryDisplay]] repeats:NO];
        }
        else {
            // kill the mag if it's showing
            [self.secondaryDisplay removeMagnifyingGlass];
        }
    }
}

#pragma mark - views

- (BOOL)isPointInGamePlayArea:(CGPoint)point {
    CGRect boundaryRect = kGamePlayHitArea;
    
    if (!CGRectContainsPoint(boundaryRect, point)) {
        // NSLog(@"out of bounds");
        return NO;
    }
    
    return YES;
}

- (void)showTitle {
    if (self.titleDisplay.hidden == YES) {
        theMainDisplay = self.titleDisplay;
        [self.titleDisplay startAnimating];
        [self.secondaryDisplay stopAnimating];
    }
    
    dispatch_async(dispatch_get_main_queue(), ^{
    double delayInSeconds = 0.;
    dispatch_time_t popTime = dispatch_time(DISPATCH_TIME_NOW, (int64_t)(delayInSeconds * NSEC_PER_SEC));
        dispatch_after(popTime, dispatch_get_main_queue(), ^(void){
            self.titleDisplay.hidden = NO;
            self.secondaryDisplay.hidden = YES;
        });
    });
}

- (void)showAuxillaryScreensWithDirectionalControls:(BOOL)controls {
    if (self.titleDisplay.hidden == NO) {
        theMainDisplay = self.secondaryDisplay;
        [self.secondaryDisplay startAnimating];
        [self.titleDisplay stopAnimating];
    }
    
    self.titleDisplay.hidden = YES;
    self.secondaryDisplay.hidden = NO;
    
    dispatch_async(dispatch_get_main_queue(), ^{
        double delayInSeconds = 0.;
        dispatch_time_t popTime = dispatch_time(DISPATCH_TIME_NOW, (int64_t)(delayInSeconds * NSEC_PER_SEC));
        dispatch_after(popTime, dispatch_get_main_queue(), ^(void){
            
            self.titleDisplay.hidden = YES;
            self.secondaryDisplay.hidden = NO;
            
            self.playerControlView.hidden = !controls;
        });
    });
    
}

#pragma mark - keyboard stuff

- (void)showKeyboard {
    dispatch_async(dispatch_get_main_queue(), ^{
        self.aTextField.text = @"Recording";
        [self.aTextField becomeFirstResponder];
    });
}

- (void)viewDidUnload {
    [self setPlayerControlView:nil];
    [self setATextField:nil];
    [self setEscButton:nil];
    [self setButtonView:nil];
    [super viewDidUnload];
}

- (uint)cachedKeyStrokeCount {
    return [self.cachedKeyStrokes count];
}

- (char)dequeKeyStroke {
    NSString *keyStroke = [self.cachedKeyStrokes objectAtIndex:0];
    @synchronized(self.cachedKeyStrokes){
        [self.cachedKeyStrokes removeObjectAtIndex:0];
    }
    
    return [keyStroke characterAtIndex:0];
}

#pragma mark - UITextFieldDelegate

- (void)didHideKeyboard {
    if ([self.cachedKeyStrokes count] == 0) {
        [self.cachedKeyStrokes addObject:kESC_Key];
    }

    self.escButton.hidden = YES;
}

- (void)didShowKeyboard {
    self.escButton.hidden = NO;
}

- (BOOL)textFieldShouldReturn:(UITextField *)textField {
    [self.cachedKeyStrokes addObject:@"\015"];
    [textField resignFirstResponder];
    return YES;
}

- (BOOL)textField:(UITextField *)textField shouldChangeCharactersInRange:(NSRange)range replacementString:(NSString *)string {
    const char *_char = [string cStringUsingEncoding:NSUTF8StringEncoding];
    int isBackSpace = strcmp(_char, "\b");
    
    if (isBackSpace == -8) {
        // is backspace
        [self.cachedKeyStrokes addObject:@"\177"];
    }
    else if([string isEqualToString:@"\n"]) {
        [textField resignFirstResponder];
        // enter
        [self.cachedKeyStrokes addObject:@"\015"];
    }
    else {
        // misc
        [self.cachedKeyStrokes addObject:string];
    }
    
    return YES;
}

#pragma mark - Actions

- (IBAction)escButtonPressed:(id)sender {
    [self.cachedKeyStrokes addObject:@"\033"];
    [self.aTextField resignFirstResponder];
}

- (IBAction)upButtonPressed:(id)sender {
    [self.cachedKeyStrokes addObject:@"k"];
}

- (IBAction)downButtonPressed:(id)sender {
    [self.cachedKeyStrokes addObject:@"j"];
}

- (IBAction)rightButtonPressed:(id)sender {
    [self.cachedKeyStrokes addObject:@"l"];
}

- (IBAction)leftButtonPressed:(id)sender {
    [self.cachedKeyStrokes addObject:@"h"];
}

- (IBAction)upLeftButtonPressed:(id)sender {
    [self.cachedKeyStrokes addObject:@"y"];
}

- (IBAction)upRightButtonPressed:(id)sender {
    [self.cachedKeyStrokes addObject:@"u"];
}

- (IBAction)downLeftButtonPressed:(id)sender {
    [self.cachedKeyStrokes addObject:@"b"];
}

- (IBAction)downRightButtonPressed:(id)sender {
    [self.cachedKeyStrokes addObject:@"n"];
}

- (IBAction)seedKeyPressed:(id)sender {
    _seedKeyDown = !_seedKeyDown;
    
    if (_seedKeyDown) {
        [self.seedButton setImage:[UIImage imageNamed:@"brogue_sproutedseed.png"] forState:UIControlStateNormal];
    }
    else {
        [self.seedButton setImage:[UIImage imageNamed:@"brogue_seed.png"] forState:UIControlStateNormal];
    }
}

- (IBAction)showLeaderBoardButtonPressed:(id)sender {
    [self rgGCshowLeaderBoardWithCategory:kBrogueHighScoreLeaderBoard];
}

- (IBAction)aboutButtonPressed:(id)sender {
    self.modalPresentationStyle = UIModalPresentationFormSheet;
    AboutViewController *aboutVC = [[AboutViewController alloc] init];
    aboutVC.modalPresentationStyle = UIModalPresentationFormSheet;
    [self presentViewController:aboutVC animated:YES completion:nil];
}

- (IBAction)showInventoryButtonPressed:(id)sender {
    @synchronized(self.cachedKeyStrokes){
        [self.cachedKeyStrokes removeAllObjects];
        [self.cachedKeyStrokes addObject:@"i"];
    }
}

#pragma mark - setters/getters

- (void)setBlockMagView:(BOOL)blockMagView {
    _blockMagView = blockMagView;
    
    if (blockMagView) {
        [self.secondaryDisplay removeMagnifyingGlass];
    }
}

- (void)showInventoryOnDeathButton:(BOOL)show {
    dispatch_async(dispatch_get_main_queue(), ^{
        self.showInventoryButton.hidden = !show;
        
        if (show) {
            self.seedLabel.hidden = NO;
            [self.seedLabel setText:[NSString stringWithFormat:@"Seed:%li", [RogueDriver rogueSeed]]];
        }
        else {
            self.seedLabel.hidden = YES;
        }
    });
}

- (void)hideKeyboard {
    dispatch_async(dispatch_get_main_queue(), ^{
        [self.aTextField becomeFirstResponder];
        [self.aTextField resignFirstResponder];
    });
}

// my original intention was to not touch any game code. In the end this was not possible in order to give the best user experience. I funnel all modification and events in the core code through here.
- (void)setBrogueGameEvent:(BrogueGameEvent)brogueGameEvent {
    _lastBrogueGameEvent = brogueGameEvent;
    
    switch (brogueGameEvent) {
        case BrogueGameEventWaitingForConfirmation:
        case BrogueGameEventActionMenuOpen:
        case BrogueGameEventOpenedInventory:
            self.blockMagView = YES;
            break;
        case BrogueGameEventInventoryItemAction:
        case BrogueGameEventConfirmationComplete:
        case BrogueGameEventActionMenuClose:
        case BrogueGameEventClosedInventory:
            self.blockMagView = NO;
            break;
        case BrogueGameEventKeyBoardInputRequired:
            [self showKeyboard];
            break;
        case BrogueGameEventShowTitle:
        case BrogueGameEventOpenGameFinished:
            [self showInventoryOnDeathButton:NO];
            [self showTitle];
            [self hideKeyboard];
            self.blockMagView = YES;
            break;
        case BrogueGameEventStartNewGame:
        case BrogueGameEventOpenGame:
            [self showAuxillaryScreensWithDirectionalControls:YES];
            self.blockMagView = NO;
            break;
        case BrogueGameEventPlayRecording:
        case BrogueGameEventShowHighScores:
        case BrogueGameEventPlayBackPanic:
            [self showAuxillaryScreensWithDirectionalControls:NO];
            self.blockMagView = YES;
            break;
        case BrogueGameEventMessagePlayerHasDied:
            [self showInventoryOnDeathButton:YES];
            break;
        case BrogueGameEventPlayerHasDiedMessageAcknowledged:
            [self showInventoryOnDeathButton:NO];
            break;
        default:
            break;
    }
}

@end
