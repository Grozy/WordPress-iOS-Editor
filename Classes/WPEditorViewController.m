#import "WPEditorViewController.h"
#import "WPKeyboardToolbarBase.h"
#import "WPKeyboardToolbarDone.h"
#import <WordPress-iOS-Shared/WPStyleGuide.h>
#import <WordPress-iOS-Shared/WPTableViewCell.h>
#import <WordPress-iOS-Shared/UIImage+Util.h>
#import <UIAlertView+Blocks/UIAlertView+Blocks.h>
#import "UIWebView+AccessoryHiding.h"
#import "WPInsetTextField.h"

CGFloat const EPVCTextfieldHeight = 44.0f;
CGFloat const EPVCStandardOffset = 15.0;

@interface WPEditorViewController ()<UITextFieldDelegate, UITextViewDelegate, WPKeyboardToolbarDelegate>
@property (nonatomic) CGPoint scrollOffsetRestorePoint;
@property (nonatomic, strong) UIAlertView *alertView;
@property (nonatomic, strong) UIWebView *editorView;
@property (nonatomic, strong) UITextField *titleTextField;
@property (nonatomic, strong) WPKeyboardToolbarBase *editorToolbar;
@property (nonatomic, strong) WPKeyboardToolbarDone *titleToolbar;
@property (nonatomic) BOOL didFinishLoadingEditor;
@property (nonatomic, strong) UIWindow *keyboardWindow;
@end

@implementation WPEditorViewController

@synthesize titleText = _titleText;
@synthesize bodyText = _bodyText;

- (void)viewDidLoad
{
    [super viewDidLoad];
    
    // For the iPhone, let's let the overscroll background color be white to match the editor.
    if (IS_IPAD) {
        self.view.backgroundColor = [WPStyleGuide itsEverywhereGrey];
    }
    self.navigationController.navigationBar.translucent = NO;
    [self setupToolbar];
    [self setupTextViews];
}

- (void)viewWillAppear:(BOOL)animated
{
    [super viewWillAppear:animated];
    
    // When restoring state, the navigationController is nil when the view loads,
    // so configure its appearance here instead.
    self.navigationController.navigationBar.translucent = NO;
    self.navigationController.toolbarHidden = NO;
    UIToolbar *toolbar = self.navigationController.toolbar;
    toolbar.barTintColor = [WPStyleGuide itsEverywhereGrey];
    toolbar.translucent = NO;
    toolbar.barStyle = UIBarStyleDefault;
    
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(keyboardWillShow:)
                                                 name:UIKeyboardWillShowNotification
                                               object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(keyboardDidShow:)
                                                 name:UIKeyboardDidShowNotification
                                               object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(keyboardWillHide:)
                                                 name:UIKeyboardWillHideNotification
                                               object:nil];
    
    if(self.navigationController.navigationBarHidden) {
        [self.navigationController setNavigationBarHidden:NO animated:animated];
    }
    
    if (self.navigationController.toolbarHidden) {
        [self.navigationController setToolbarHidden:NO animated:animated];
    }
    
    for (UIView *view in self.navigationController.toolbar.subviews) {
        [view setExclusiveTouch:YES];
    }
    
//TODO:    [self.textView setContentOffset:CGPointMake(0, 0)];
}

- (void)viewDidAppear:(BOOL)animated
{
    [super viewDidAppear:animated];
    [self refreshUI];
}

- (void)viewWillDisappear:(BOOL)animated
{
    [super viewWillDisappear:animated];
    [[NSNotificationCenter defaultCenter] removeObserver:self name:UIKeyboardWillShowNotification object:nil];
    [[NSNotificationCenter defaultCenter] removeObserver:self name:UIKeyboardDidShowNotification object:nil];
    [[NSNotificationCenter defaultCenter] removeObserver:self name:UIKeyboardWillHideNotification object:nil];
    [self.navigationController setToolbarHidden:YES animated:animated];
	[self stopEditing];
}

- (void)didReceiveMemoryWarning {
    [super didReceiveMemoryWarning];
}

#pragma mark - Getters and Setters

- (NSString*)titleText
{
    return _titleText;
}

- (void) setTitleText:(NSString*)titleText
{
    _titleText = titleText;
    [self refreshUI];
}

- (NSString*)bodyText
{
    return _bodyText;
}

- (void) setBodyText:(NSString*)bodyText
{
    _bodyText = bodyText;
    [self refreshUI];
}

#pragma mark - View Setup

- (void)setupToolbar
{
    if ([self.toolbarItems count] > 0) {
        return;
    }
    
    UIBarButtonItem *previewButton = [[UIBarButtonItem alloc] initWithImage:[UIImage imageNamed:@"icon-posts-editor-preview"]
                                                                      style:UIBarButtonItemStylePlain
                                                                     target:self
                                                                     action:@selector(didTouchPreview)];
    UIBarButtonItem *photoButton = [[UIBarButtonItem alloc] initWithImage:[UIImage imageNamed:@"icon-posts-editor-media"]
                                                                    style:UIBarButtonItemStylePlain
                                                                   target:self
                                                                   action:@selector(didTouchMediaOptions)];
    UIBarButtonItem *optionsButton = [[UIBarButtonItem alloc] initWithImage:[UIImage imageNamed:@"icon-menu-settings"]
                                                                      style:UIBarButtonItemStylePlain
                                                                     target:self
                                                                     action:@selector(didTouchSettings)];
    
    previewButton.tintColor = [WPStyleGuide textFieldPlaceholderGrey];
    photoButton.tintColor = [WPStyleGuide textFieldPlaceholderGrey];
    optionsButton.tintColor = [WPStyleGuide textFieldPlaceholderGrey];

    previewButton.accessibilityLabel = NSLocalizedString(@"Preview post", nil);
    photoButton.accessibilityLabel = NSLocalizedString(@"Add media", nil);
    optionsButton.accessibilityLabel = NSLocalizedString(@"Options", @"Title of the Post Settings tableview cell in the Post Editor. Tapping shows settings and options related to the post being edited.");
    
    UIBarButtonItem *leftFixedSpacer = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemFixedSpace
                                                                                     target:nil
                                                                                     action:nil];
    UIBarButtonItem *rightFixedSpacer = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemFixedSpace
                                                                                      target:nil
                                                                                      action:nil];
    UIBarButtonItem *centerFlexSpacer = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemFlexibleSpace
                                                                                      target:nil
                                                                                      action:nil];
    
    leftFixedSpacer.width = -2.0f;
    rightFixedSpacer.width = -5.0f;
    
    self.toolbarItems = @[leftFixedSpacer, photoButton, centerFlexSpacer, optionsButton, centerFlexSpacer, previewButton, rightFixedSpacer];
}

- (void)setupTextViews
{
    CGFloat viewWidth = CGRectGetWidth(self.view.frame);
    UIViewAutoresizing mask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    CGRect frame = CGRectMake(0.0f, 0.0f, viewWidth, EPVCTextfieldHeight);
    
    // Title TextField.
    if (!self.titleTextField) {
        self.titleTextField = [[WPInsetTextField alloc] initWithFrame:frame];
        self.titleTextField.returnKeyType = UIReturnKeyDone;
        self.titleTextField.delegate = self;
        self.titleTextField.font = [WPStyleGuide postTitleFont];
        self.titleTextField.backgroundColor = [UIColor whiteColor];
        self.titleTextField.textColor = [WPStyleGuide darkAsNightGrey];
        self.titleTextField.autoresizingMask = UIViewAutoresizingFlexibleWidth;
        self.titleTextField.attributedPlaceholder = [[NSAttributedString alloc] initWithString:(NSLocalizedString(@"Enter title here", @"Label for the title of the post field. Should be the same as WP core.")) attributes:(@{NSForegroundColorAttributeName: [WPStyleGuide textFieldPlaceholderGrey]})];
        self.titleTextField.accessibilityLabel = NSLocalizedString(@"Title", @"Post title");
        self.titleTextField.keyboardType = UIKeyboardTypeAlphabet;
        self.titleTextField.returnKeyType = UIReturnKeyNext;
    }
    [self.view addSubview:self.titleTextField];
    
    // Editor View
    frame = CGRectMake(0.0f, frame.size.height, viewWidth, CGRectGetHeight(self.view.frame) - EPVCTextfieldHeight);
    if (!self.editorView) {
        self.editorView = [[UIWebView alloc] initWithFrame:frame];
        self.editorView.delegate = self;
        self.editorView.hidesInputAccessoryView = YES;
        self.editorView.autoresizingMask = mask;
        self.editorView.scalesPageToFit = YES;
        self.editorView.dataDetectorTypes = UIDataDetectorTypeNone;
        self.editorView.scrollView.bounces = NO;
        self.editorView.backgroundColor = [UIColor whiteColor];
        [self.editorView loadRequest:[NSURLRequest requestWithURL:[NSURL fileURLWithPath:[[NSBundle mainBundle] pathForResource:@"quill_native_index" ofType:@"html"]isDirectory:NO]]];
    }
    [self.view addSubview:self.editorView];
}

- (void)positionTextView:(NSNotification *)notification
{
    NSDictionary *keyboardInfo = [notification userInfo];
    CGRect originalKeyboardFrame = [[keyboardInfo objectForKey:UIKeyboardFrameEndUserInfoKey] CGRectValue];
    CGRect keyboardFrame = [self.view convertRect:[self.view.window convertRect:originalKeyboardFrame fromWindow:nil]
                                         fromView:nil];
    CGRect frame = self.editorView.frame;
    
    if (self.isShowingKeyboard) {
        frame.size.height = CGRectGetMinY(keyboardFrame) - CGRectGetMinY(frame);
    } else {
        frame.size.height = CGRectGetHeight(self.view.frame) - EPVCTextfieldHeight;
    }
    self.editorView.frame = frame;
}

#pragma mark - Actions

- (void)didTouchSettings
{
    if ([self.delegate respondsToSelector: @selector(editorDidPressSettings:)]) {
        [self.delegate editorDidPressSettings:self];
    }
}

- (void)didTouchPreview
{
    if ([self.delegate respondsToSelector: @selector(editorDidPressPreview:)]) {
        [self.delegate editorDidPressPreview:self];
    }
}

- (void)didTouchMediaOptions
{
    if ([self.delegate respondsToSelector: @selector(editorDidPressMedia:)]) {
        [self.delegate editorDidPressMedia:self];
    }
}

#pragma mark - Editor Commands

- (void)stopEditing
{
    if ([self.titleTextField isFirstResponder]) {
        [self.titleTextField resignFirstResponder];
    }
    [self.view endEditing:YES];
}

- (void)refreshUI
{
    if(self.titleText != nil || self.titleText.length != 0) {
        self.title = self.titleText;
        [self.titleTextField setText:_titleText];
    }
    if(self.bodyText != nil || self.bodyText.length != 0) {
        [self loadEditor:self.bodyText];
    }
}

- (void)loadEditor:(NSString*)html
{
    if (_didFinishLoadingEditor) {
        [self clenseHTML:&html];
        NSString *setEditorContentCommand = [NSString stringWithFormat:@"setEditorHTML(\"%@\")", html];
        [self.editorView stringByEvaluatingJavaScriptFromString:setEditorContentCommand];
    }
}

- (void)showLinkAlert
{
    NSString *alertViewTitle = NSLocalizedString(@"Make a Link", @"Title of the Link Helper popup to aid in creating a Link in the Post Editor.");
    NSCharacterSet *charSet = [NSCharacterSet whitespaceAndNewlineCharacterSet];
    alertViewTitle = [alertViewTitle stringByTrimmingCharactersInSet:charSet];
    
    NSString *insertButtonTitle = NSLocalizedString(@"Insert", @"Insert content (link, media) button");
    NSString *cancelButtonTitle = NSLocalizedString(@"Cancel", @"Cancel button");
    
    self.alertView = [[UIAlertView alloc] initWithTitle:alertViewTitle
                                            message:nil
                                           delegate:nil
                                  cancelButtonTitle:cancelButtonTitle
                                  otherButtonTitles:insertButtonTitle, nil];
    self.alertView.alertViewStyle = UIAlertViewStylePlainTextInput;
    self.alertView.tag = 99;
    
    UITextField *linkURL = [self.alertView textFieldAtIndex:0];
    linkURL.placeholder = NSLocalizedString(@"Link URL", @"Popup to aid in creating a Link in the Post Editor, URL field (where you can type or paste a URL that the text should link.");
    linkURL.autocapitalizationType = UITextAutocapitalizationTypeNone;
    linkURL.keyboardAppearance = UIKeyboardAppearanceAlert;
    linkURL.keyboardType = UIKeyboardTypeURL;
    linkURL.autocorrectionType = UITextAutocorrectionTypeNo;
    __weak __typeof(self)weakSelf = self;
    self.alertView.tapBlock = ^(UIAlertView *alertView, NSInteger buttonIndex) {
        if (alertView.tag == 99) {
            if (buttonIndex == 1) {
                // Insert link
                UITextField *urlField = [alertView textFieldAtIndex:0];
                
                if ((urlField.text == nil) || ([urlField.text isEqualToString:@""])) {
                    return;
                }
                
                NSString *urlString = [weakSelf validateNewLinkInfo:[urlField.text stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]]];
                NSLog(@"Entered: %@",urlString);
                [self clenseHTML:&urlString];
                NSString *jsCommand = [NSString stringWithFormat:@"linkSelection(\"%@\")", urlString];
                [weakSelf.editorView stringByEvaluatingJavaScriptFromString:jsCommand];
            }
            
            // Don't dismiss the keyboard
            // Hack from http://stackoverflow.com/a/7601631
            dispatch_async(dispatch_get_main_queue(), ^{
                if([weakSelf.editorView resignFirstResponder] || [weakSelf.titleTextField resignFirstResponder]){
                    [weakSelf.editorView becomeFirstResponder];
                }
            });
        }
    };
    
    self.alertView.shouldEnableFirstOtherButtonBlock = ^BOOL(UIAlertView *alertView) {
        if (alertView.tag == 99) {
            UITextField *textField = [alertView textFieldAtIndex:0];
            if ([textField.text length] == 0) {
                return NO;
            }
        }
        return YES;
    };

    [self.alertView show];
}

// Appends http:// if protocol part is not there as part of urlText.
- (NSString *)validateNewLinkInfo:(NSString *)urlText
{
    NSError *error = nil;
    NSRegularExpression *regex = [NSRegularExpression regularExpressionWithPattern:@"^[\\w]+:" options:0 error:&error];
    
    if ([regex numberOfMatchesInString:urlText options:0 range:NSMakeRange(0, [urlText length])] > 0) {
        return urlText;
    } else if([urlText hasPrefix:@"#"]) {
        // link to named anchor
        return urlText;
    } else {
        return [NSString stringWithFormat:@"http://%@", urlText];
    }
}

#pragma mark - WPKeyboardToolbar Delegate

- (void)keyboardToolbarButtonItemPressed:(WPKeyboardToolbarButtonItem *)buttonItem
{
    NSString *jsCommand;
    if ([buttonItem.actionTag isEqualToString:@"strong"]) {
        jsCommand = @"boldSelection();";
        [self.editorView stringByEvaluatingJavaScriptFromString:jsCommand];
    } else if ([buttonItem.actionTag isEqualToString:@"em"]) {
        jsCommand= @"italicizeSelection();";
        [self.editorView stringByEvaluatingJavaScriptFromString:jsCommand];
    } else if ([buttonItem.actionTag isEqualToString:@"u"]) {
        jsCommand = @"underlineSelection();";
        [self.editorView stringByEvaluatingJavaScriptFromString:jsCommand];
    } else if ([buttonItem.actionTag isEqualToString:@"del"]) {
        jsCommand = @"deleteSelection();";
        [self.editorView stringByEvaluatingJavaScriptFromString:jsCommand];
    } else if ([buttonItem.actionTag isEqualToString:@"link"]) {
        [self showLinkAlert];
    } else if ([buttonItem.actionTag isEqualToString:@"image"]) {
        NSString *urlString = @"http://freshtakeoncontent.com/wp-content/uploads/Wordpress_256.png";
        [self clenseHTML:&urlString];
        jsCommand = [NSString stringWithFormat:@"insertImage(\"%@\")", urlString];
        [self.editorView stringByEvaluatingJavaScriptFromString:jsCommand];
    } else if ([buttonItem.actionTag isEqualToString:@"more"]) {
        jsCommand= @"insertMore();";
        [self.editorView stringByEvaluatingJavaScriptFromString:jsCommand];
    } else if ([buttonItem.actionTag isEqualToString:@"done"]) {
        if ([self.editorView isFirstResponder]) {
            [self.editorView resignFirstResponder];
        }
        [self.view endEditing:YES];
    }
}

#pragma mark - UIWebViewDelegate Delegate Methods

- (void)webViewDidFinishLoad:(UIWebView *)webView
{
    self.didFinishLoadingEditor = YES;
    [self refreshUI];
}

- (BOOL)webView:(UIWebView *)webView shouldStartLoadWithRequest:(NSURLRequest *)request navigationType:(UIWebViewNavigationType)navigationType
{
    if([[[request URL] absoluteString] isEqualToString:@"app://api-triggered-text-change"] || [[[request URL] absoluteString] isEqualToString:@"app://user-triggered-text-change"]) {
        NSString *html = [self.editorView stringByEvaluatingJavaScriptFromString:@"getEditorHTML();"];
        self.bodyText = html;
        if ([self.delegate respondsToSelector: @selector(editorTextDidChange:)]) {
            [self.delegate editorTextDidChange:self];
        }
        return false;
    }
    return true;
}

#pragma mark - TextField delegate

- (BOOL)textFieldShouldBeginEditing:(UITextField *)textField
{
    if ([self.delegate respondsToSelector: @selector(editorShouldBeginEditing:)]) {
        return [self.delegate editorShouldBeginEditing:self];
    }
    return YES;
}

- (BOOL)textField:(UITextField *)textField shouldChangeCharactersInRange:(NSRange)range replacementString:(NSString *)string
{
    if (textField == self.titleTextField) {
        NSString *newTitle = [textField.text stringByReplacingCharactersInRange:range withString:string];
        [self setTitle:newTitle];
        self.titleText = newTitle;
        if ([self.delegate respondsToSelector: @selector(editorTitleDidChange:)]) {
            [self.delegate editorTitleDidChange:self];
        }
    }
    return YES;
}

- (BOOL)textFieldShouldReturn:(UITextField *)textField
{
    [self.editorView becomeFirstResponder];
    return NO;
}

#pragma mark - Positioning & Rotation

- (BOOL)shouldHideToolbarsWhileTyping
{
    /*
     Never hide for the iPad.
     Always hide on the iPhone except for portrait + external keyboard
     */
    if (IS_IPAD) {
        return NO;
    }
    
    BOOL isLandscape = UIInterfaceOrientationIsLandscape([UIApplication sharedApplication].statusBarOrientation);
    if (!isLandscape && self.isExternalKeyboard) {
        return NO;
    }
    
    return YES;
}

- (void)willAnimateRotationToInterfaceOrientation:(UIInterfaceOrientation)interfaceOrientation duration:(NSTimeInterval)duration
{
    CGRect frame = self.editorToolbar.frame;
    if (UIDeviceOrientationIsLandscape(interfaceOrientation)) {
        if (IS_IPAD) {
            frame.size.height = WPKT_HEIGHT_IPAD_LANDSCAPE;
        } else {
            frame.size.height = WPKT_HEIGHT_IPHONE_LANDSCAPE;
        }
        
    } else {
        if (IS_IPAD) {
            frame.size.height = WPKT_HEIGHT_IPAD_PORTRAIT;
        } else {
            frame.size.height = WPKT_HEIGHT_IPHONE_PORTRAIT;
        }
    }
    self.editorToolbar.frame = frame;
    self.titleToolbar.frame = frame; // Frames match, no need to re-calc.
}

#pragma mark - Keyboard management

- (void)keyboardWillShow:(NSNotification *)notification
{
	self.isShowingKeyboard = YES;
    
    if ([self shouldHideToolbarsWhileTyping]) {
        [[UIApplication sharedApplication] setStatusBarHidden:YES withAnimation:UIStatusBarAnimationFade];
        [self.navigationController setNavigationBarHidden:YES animated:YES];
        [self.navigationController setToolbarHidden:YES animated:NO];
    }
    
    for (UIWindow *testWindow in [[UIApplication sharedApplication] windows]) {
        if (![[testWindow class] isEqual:[UIWindow class]]) {
            _keyboardWindow = testWindow;
            break;
        }
    }
    
    CGRect frm = _keyboardWindow.frame;
    CGRect toolbarFrame = CGRectMake(0.0f, frm.size.height, frm.size.width, 44.0f);
    if (_editorToolbar == nil) {
        _editorToolbar = [[WPKeyboardToolbarBase alloc] initWithFrame:toolbarFrame];
        _editorToolbar.backgroundColor = [WPStyleGuide keyboardColor];
        _editorToolbar.delegate = self;
    }
    
    [_keyboardWindow addSubview:_editorToolbar];
    
    [UIView animateWithDuration:0.30 animations:^{
        _editorToolbar.frame = CGRectMake(0.0f, 308.0f, toolbarFrame.size.width, toolbarFrame.size.height);
    }];
    
    _editorToolbar.frame = CGRectMake(0.0f, 308.0f, toolbarFrame.size.width, toolbarFrame.size.height);
    _isShowingKeyboard = YES;
}

- (void)keyboardDidShow:(NSNotification *)notification
{
//TODO: Restore point
//    if ([self.editorView isFirstResponder]) {
//        if (!CGPointEqualToPoint(CGPointZero, self.scrollOffsetRestorePoint)) {
//            self.textView.contentOffset = self.scrollOffsetRestorePoint;
//            self.scrollOffsetRestorePoint = CGPointZero;
//        }
//    }
    [self positionTextView:notification];
}

- (void)keyboardWillHide:(NSNotification *)notification
{
	self.isShowingKeyboard = NO;
    [[UIApplication sharedApplication] setStatusBarHidden:NO withAnimation:UIStatusBarAnimationFade];
    [self.navigationController setNavigationBarHidden:NO animated:YES];
    [self.navigationController setToolbarHidden:NO animated:NO];
    [self positionTextView:notification];
}

#pragma mark - Utility Methods

- (void)clenseHTML:(NSString **)htmlParam_p
{
    *htmlParam_p = [*htmlParam_p stringByReplacingOccurrencesOfString:@"\"" withString:@"\\\""];
    *htmlParam_p = [*htmlParam_p stringByReplacingOccurrencesOfString:@"\n" withString:@"\\n"];
    *htmlParam_p = [*htmlParam_p stringByReplacingOccurrencesOfString:@"\r" withString:@""];
    *htmlParam_p = [*htmlParam_p stringByReplacingOccurrencesOfString:@"\'" withString:@"\\\'"];
}

@end
