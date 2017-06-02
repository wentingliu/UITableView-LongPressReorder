//
//  LPRTableView.m
//
//  Copyright (c) 2013 Ben Vogelzang.
//

#import "UITableView+LongPressReorder.h"
#import <QuartzCore/QuartzCore.h>
#import <objc/runtime.h>


// The basic idea is simple: we add a long press gesture to the tableView, once the gesture is activated,
// a placeholder view is created for the pressed cell, then we move the placeholder view as the touch goes on.
@interface LPRTableViewProxy : NSObject <LPRTableViewDelegate>

@property (nonatomic, readonly) UITableView *tableView;
@property (nonatomic, assign) CGFloat draggingViewOpacity;
@property (nonatomic, assign) CGFloat draggingViewScale;
@property (nonatomic, assign) BOOL draggingViewIsCentered;
@property (nonatomic, assign) BOOL canReorder;
@property (nonatomic, strong) UILongPressGestureRecognizer *longPress;
@property (nonatomic, strong) CADisplayLink *scrollDisplayLink;
@property (nonatomic, assign) CGFloat scrollRate;
@property (nonatomic, strong) NSIndexPath *currentIndexPath;
@property (nonatomic, strong) NSIndexPath *initialIndexPath;
@property (nonatomic, strong) UIView *draggingView;

@end


@implementation LPRTableViewProxy

- (instancetype)initWithTableView:(UITableView *)tableView {
    self = [super init];
    if (self) {
        _tableView = tableView;
        _longPress = [[UILongPressGestureRecognizer alloc] initWithTarget:self action:@selector(longPress:)];
        [_tableView addGestureRecognizer:_longPress];

        _canReorder = YES;
        _draggingViewOpacity = 0.85;
        _draggingViewScale = 1;
        _longPress.enabled = _canReorder;
    }
    
    return self;
}

- (void)setCanReorder:(BOOL)canReorder {
    _canReorder = canReorder;
    _longPress.enabled = _canReorder;
    if (!canReorder) {
        [self stopDisplayLinkUpdating];
        [self removeDraggingView];
    }
}

- (void)longPress:(UILongPressGestureRecognizer *)gesture {
    
    CGPoint locationInContainer = [self locationInContainer:gesture];
    CGPoint locationInTable = [gesture locationInView:_tableView];
    NSIndexPath *indexPath = [_tableView indexPathForRowAtPoint:locationInTable];
    
    int sections = [_tableView numberOfSections];
    int rows = 0;
    for(int i = 0; i < sections; i++) {
        rows += [_tableView numberOfRowsInSection:i];
    }
    
    // get out of here if the long press was not on a valid row or our table is empty
    // or the dataSource tableView:canMoveRowAtIndexPath: doesn't allow moving the row
    if (rows == 0 || (gesture.state == UIGestureRecognizerStateBegan && indexPath == nil) ||
        (gesture.state == UIGestureRecognizerStateEnded && self.currentIndexPath == nil) ||
        (gesture.state == UIGestureRecognizerStateBegan &&
         [_tableView.dataSource respondsToSelector:@selector(tableView:canMoveRowAtIndexPath:)] &&
         indexPath && ![_tableView.dataSource tableView:_tableView canMoveRowAtIndexPath:indexPath])) {
        [self cancelGesture];
        return;
    }
    
    // started
    if (gesture.state == UIGestureRecognizerStateBegan) {
        
        UITableViewCell *cell = [_tableView cellForRowAtIndexPath:indexPath];
        [cell setSelected:NO animated:NO];
        [cell setHighlighted:NO animated:NO];
        
        // create view that we will drag around the screen
        if (!_draggingView) {
            if ([(id)_tableView.lprDelegate respondsToSelector:@selector(tableView:draggingViewForCellAtIndexPath:)]) {
                _draggingView = [_tableView.lprDelegate tableView:_tableView draggingViewForCellAtIndexPath:indexPath];
            } else {
                // make a snapshot from the pressed tableview cell
                _draggingView = [cell snapshotViewAfterScreenUpdates:NO];
                if (!_draggingView) {
                    // make an image from the pressed tableview cell
                    UIGraphicsBeginImageContextWithOptions(cell.bounds.size, NO, 0);
                    [cell drawViewHierarchyInRect:cell.bounds afterScreenUpdates:YES];
                    UIImage *cellImage = UIGraphicsGetImageFromCurrentImageContext();
                    UIGraphicsEndImageContext();
                    _draggingView = [[UIImageView alloc] initWithImage:cellImage];
                }
            }
            
            [[self container] addSubview:_draggingView];
            CGRect frame = [self rowFrameInContainer:indexPath];
            _draggingView.frame = CGRectOffset(_draggingView.bounds, frame.origin.x, frame.origin.y);
            
            // add a show animation
            [UIView animateWithDuration:0.3
                             animations:^{
                                 if ([(id)_tableView.lprDelegate respondsToSelector:@selector(tableView:showDraggingView:atIndexPath:)]) {
                                     [_tableView.lprDelegate tableView:_tableView showDraggingView:_draggingView atIndexPath:indexPath];
                                 }
                                 // add drop shadow to image and lower opacity
                                 _draggingView.layer.masksToBounds = NO;
                                 _draggingView.layer.shadowColor = [[UIColor blackColor] CGColor];
                                 _draggingView.layer.shadowOffset = CGSizeMake(0, 0);
                                 _draggingView.layer.shadowRadius = 2.0;
                                 _draggingView.layer.shadowOpacity = 0.5;
                                 _draggingView.layer.opacity = self.draggingViewOpacity;
                                 
                                 _draggingView.transform = CGAffineTransformMakeScale(_draggingViewScale, _draggingViewScale);
                                 _draggingView.center = CGPointMake(_draggingViewIsCentered ? _tableView.center.x : locationInContainer.x, locationInContainer.y);
                             }];
        }
        
        cell.hidden = YES;
        
        self.currentIndexPath = indexPath;
        self.initialIndexPath = indexPath;
        
        [self tapticEngineFeedback];
        
        // enable scrolling for cell
        [self startDisplayLinkUpdating];
    }
    // dragging
    else if (gesture.state == UIGestureRecognizerStateChanged) {
        // update position of the drag view
        _draggingView.center = CGPointMake(_draggingViewIsCentered ? _tableView.center.x : locationInContainer.x, locationInContainer.y);
        
        [self updateCurrentIndexPath:gesture];
        
        CGRect rect = _tableView.bounds;
        // adjust rect for content inset as we will use it below for calculating scroll zones
        rect.size.height -= _tableView.contentInset.top;
        
        // tell us if we should scroll and which direction
        CGFloat scrollZoneHeight = rect.size.height / 6;
        CGFloat bottomScrollBeginning = _tableView.contentOffset.y + _tableView.contentInset.top + rect.size.height - scrollZoneHeight;
        CGFloat topScrollBeginning = _tableView.contentOffset.y + _tableView.contentInset.top  + scrollZoneHeight;
        // we're in the bottom zone
        if (locationInTable.y >= bottomScrollBeginning) {
            _scrollRate = (locationInTable.y - bottomScrollBeginning) / scrollZoneHeight;
        }
        // we're in the top zone
        else if (locationInTable.y <= topScrollBeginning) {
            _scrollRate = (locationInTable.y - topScrollBeginning) / scrollZoneHeight;
        }
        else {
            _scrollRate = 0;
        }
    }
    // dropped
    else if (gesture.state == UIGestureRecognizerStateEnded) {
        NSIndexPath *indexPath = self.currentIndexPath;
        
        // remove scrolling CADisplayLink
        [self stopDisplayLinkUpdating];
        
        // animate the drag view to the newly hovered cell
        if (_draggingView) {
            [self tapticEngineFeedback];
            [UIView animateWithDuration:0.3
                             animations:^{
                                 if ([(id)_tableView.lprDelegate respondsToSelector:@selector(tableView:hideDraggingView:atIndexPath:)]) {
                                     [_tableView.lprDelegate tableView:_tableView hideDraggingView:_draggingView atIndexPath:indexPath];
                                 }
                                 CGRect frame = [self rowFrameInContainer:indexPath];
                                 _draggingView.transform = CGAffineTransformIdentity;
                                 _draggingView.frame = CGRectOffset(_draggingView.bounds, frame.origin.x, frame.origin.y);
                             } completion:^(BOOL finished) {
                                 [_tableView beginUpdates];
                                 [_tableView deleteRowsAtIndexPaths:[NSArray arrayWithObject:indexPath] withRowAnimation:UITableViewRowAnimationNone];
                                 [_tableView insertRowsAtIndexPaths:[NSArray arrayWithObject:indexPath] withRowAnimation:UITableViewRowAnimationNone];
                                 [_tableView endUpdates];
                                 
                                 [self removeDraggingView];
                                 
                                 // reload the rows that were affected just to be safe
                                 NSMutableArray *visibleRows = [[_tableView indexPathsForVisibleRows] mutableCopy];
                                 [visibleRows removeObject:indexPath];
                                 [_tableView reloadRowsAtIndexPaths:visibleRows withRowAnimation:UITableViewRowAnimationNone];
                                 
                                 _currentIndexPath = nil;
                             }];
        }
    }
}

- (void)updateCurrentIndexPath:(UILongPressGestureRecognizer *)gesture {
    // refresh index path
    CGPoint location  = [gesture locationInView:_tableView];
    NSIndexPath *newIndexPath = [_tableView indexPathForRowAtPoint:location];
    NSIndexPath *oldIndexPath = self.currentIndexPath;
    
    if ([_tableView.delegate respondsToSelector:@selector(tableView:targetIndexPathForMoveFromRowAtIndexPath:toProposedIndexPath:)]) {
        newIndexPath = [_tableView.delegate tableView:_tableView targetIndexPathForMoveFromRowAtIndexPath:self.initialIndexPath toProposedIndexPath:newIndexPath];
    }
    
    NSInteger oldHeight = [_tableView rectForRowAtIndexPath:oldIndexPath].size.height;
    NSInteger newHeight = [_tableView rectForRowAtIndexPath:newIndexPath].size.height;
    
    if (newIndexPath && ![newIndexPath isEqual:oldIndexPath] &&
        [gesture locationInView:[_tableView cellForRowAtIndexPath:newIndexPath]].y > newHeight - oldHeight) {
        [_tableView beginUpdates];
        [_tableView moveRowAtIndexPath:self.currentIndexPath toIndexPath:newIndexPath];
        
        if ([(id)_tableView.dataSource respondsToSelector:@selector(tableView:moveRowAtIndexPath:toIndexPath:)]) {
            [_tableView.dataSource tableView:_tableView moveRowAtIndexPath:self.currentIndexPath toIndexPath:newIndexPath];
        } else {
            NSLog(@"moveRowAtIndexPath:toIndexPath: is not implemented");
        }
        [_tableView endUpdates];
        
        [self tapticEngineFeedback];
        
        _currentIndexPath = newIndexPath;
    }
}

- (void)scrollTableWithCell:(NSTimer *)timer {    
    UILongPressGestureRecognizer *gesture = _longPress;
    CGPoint locationInContainer  = [self locationInContainer:gesture];
    
    CGPoint currentOffset = _tableView.contentOffset;
    CGPoint newOffset = CGPointMake(currentOffset.x, currentOffset.y + self.scrollRate * 10);
    
    if (newOffset.y < -_tableView.contentInset.top) {
        newOffset.y = -_tableView.contentInset.top;
    } else if (_tableView.contentSize.height + _tableView.contentInset.bottom < _tableView.frame.size.height) {
        newOffset = currentOffset;
    } else if (newOffset.y > (_tableView.contentSize.height + _tableView.contentInset.bottom) - _tableView.frame.size.height) {
        newOffset.y = (_tableView.contentSize.height + _tableView.contentInset.bottom) - _tableView.frame.size.height;
    }
    
    if (newOffset.y != currentOffset.y) {
        [_tableView setContentOffset:newOffset];
        [self updateCurrentIndexPath:gesture];
        
        // In case if the cell is regenerated by `- tableView:cellForRowAtIndexPath:`, set it hidden again
        [_tableView cellForRowAtIndexPath:self.currentIndexPath].hidden = YES;
    }
    
    if (_draggingView.center.y != locationInContainer.y) {
        _draggingView.center = CGPointMake(_draggingViewIsCentered ? _tableView.center.x : locationInContainer.x, locationInContainer.y);
    }
}

- (UIView *)container {
    return _tableView.window;
}

- (CGPoint)locationInContainer:(UIGestureRecognizer *)gestureRecognizer {
    return [gestureRecognizer locationInView:[self container]];
}

- (CGRect)rowFrameInContainer:(NSIndexPath *)indexPath {
    return [[self container] convertRect:[_tableView rectForRowAtIndexPath:indexPath] fromView:_tableView];
}

- (void)cancelGesture {
    _longPress.enabled = NO;
    _longPress.enabled = YES;
}

- (void)startDisplayLinkUpdating {
    self.scrollDisplayLink = [CADisplayLink displayLinkWithTarget:self selector:@selector(scrollTableWithCell:)];
    [self.scrollDisplayLink addToRunLoop:[NSRunLoop mainRunLoop] forMode:NSDefaultRunLoopMode];
}

- (void)stopDisplayLinkUpdating {
    [_scrollDisplayLink invalidate];
    _scrollDisplayLink = nil;
    _scrollRate = 0;
}

- (void)removeDraggingView {
    [_draggingView removeFromSuperview];
    _draggingView = nil;
}

- (void)tapticEngineFeedback {
    if ([[[UIDevice currentDevice] systemVersion] compare:@"10.0" options:NSNumericSearch] != NSOrderedAscending &&
        [UIApplication sharedApplication].keyWindow.rootViewController.traitCollection.forceTouchCapability == UIForceTouchCapabilityAvailable) {
        static UIImpactFeedbackGenerator *generator = nil;
        if (!generator) {
            generator = [UIImpactFeedbackGenerator new];
            [generator prepare];
        }
        [generator impactOccurred];
    }
}

@end


@implementation UITableView (LongPressReorder)

static void *LPRDelegateKey = &LPRDelegateKey;

- (void)setLprDelegate:(id<LPRTableViewDelegate>)LPRDelegate {
    id delegate = objc_getAssociatedObject(self, LPRDelegateKey);
    if (delegate != LPRDelegate) {
        objc_setAssociatedObject(self, LPRDelegateKey, LPRDelegate, OBJC_ASSOCIATION_ASSIGN);
    }
}

- (id <LPRTableViewDelegate>)lprDelegate {
    id delegate = objc_getAssociatedObject(self, LPRDelegateKey);
    return delegate;
}

static void *LPRLongPressEnabledKey = &LPRLongPressEnabledKey;

- (void)setLongPressReorderEnabled:(BOOL)longPressReorderEnabled {
    BOOL isEnabled = [self isLongPressReorderEnabled];
    if (isEnabled != longPressReorderEnabled) {
        NSNumber *enabled = [NSNumber numberWithBool:longPressReorderEnabled];
        objc_setAssociatedObject(self, LPRLongPressEnabledKey, enabled, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        [self lprProxy].canReorder = longPressReorderEnabled;
    }
}

- (BOOL)isLongPressReorderEnabled {
    NSNumber *enabled = objc_getAssociatedObject(self, LPRLongPressEnabledKey);
    if (enabled == nil) {
        enabled = [NSNumber numberWithBool:NO];
        objc_setAssociatedObject(self, LPRLongPressEnabledKey, enabled, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
    return [enabled boolValue];
}

static void *LPRProxyKey = &LPRProxyKey;

- (LPRTableViewProxy *)lprProxy {
    LPRTableViewProxy *proxy = objc_getAssociatedObject(self, LPRProxyKey);
    if (proxy == nil) {
        proxy = [[LPRTableViewProxy alloc] initWithTableView:self];
        objc_setAssociatedObject(self, LPRProxyKey, proxy, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
    return proxy;
}

- (BOOL)isLongPressReordering {
    return [self lprProxy].draggingView != nil;
}

- (void)setDraggingViewScale:(CGFloat)draggingViewScale {
    [[self lprProxy] setDraggingViewScale:draggingViewScale];
}

- (CGFloat)draggingViewScale {
    return [self lprProxy].draggingViewScale;
}

- (void)setDraggingViewIsCentered:(BOOL)draggingViewIsCentered {
    [[self lprProxy] setDraggingViewIsCentered:draggingViewIsCentered];
}

- (BOOL)draggingViewIsCentered {
    return [self lprProxy].draggingViewIsCentered;
}

@end
