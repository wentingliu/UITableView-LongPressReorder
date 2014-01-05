//
//  LPRTableView.m
//
//  Copyright (c) 2013 Ben Vogelzang.
//

#import "UITableView+LongPressReorder.h"
#import <QuartzCore/QuartzCore.h>
#import <objc/runtime.h>


// The basic idea is simple: we add a long press gesture to the tableView, once the gesture is activeated,
// a placeholder view is created for the pressed cell, then we move the placeholder view as the touch goes on.
@interface LPRTableViewProxy : NSObject <LPRTableViewDelegate>

@property (nonatomic, readonly) UITableView *tableView;
@property (nonatomic, assign) CGFloat draggingViewOpacity;
@property (nonatomic, assign) BOOL canReorder;
@property (nonatomic, strong) UILongPressGestureRecognizer *longPress;
@property (nonatomic, strong) CADisplayLink *scrollDisplayLink;
@property (nonatomic, assign) CGFloat scrollRate;
@property (nonatomic, strong) NSIndexPath *currentLocationIndexPath;
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
        _longPress.enabled = _canReorder;
    }
    
    return self;
}

- (void)setCanReorder:(BOOL)canReorder {
    _canReorder = canReorder;
    _longPress.enabled = _canReorder;
}

- (void)longPress:(UILongPressGestureRecognizer *)gesture {
    
    CGPoint location = [gesture locationInView:_tableView];
    NSIndexPath *indexPath = [_tableView indexPathForRowAtPoint:location];
    
    int sections = [_tableView numberOfSections];
    int rows = 0;
    for(int i = 0; i < sections; i++) {
        rows += [_tableView numberOfRowsInSection:i];
    }
    
    // get out of here if the long press was not on a valid row or our table is empty
    // or the dataSource tableView:canMoveRowAtIndexPath: doesn't allow moving the row
    if (rows == 0 || (gesture.state == UIGestureRecognizerStateBegan && indexPath == nil) ||
        (gesture.state == UIGestureRecognizerStateEnded && self.currentLocationIndexPath == nil) ||
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
                // make an image from the pressed tableview cell
                UIGraphicsBeginImageContextWithOptions(cell.bounds.size, NO, 0);
                [cell.layer renderInContext:UIGraphicsGetCurrentContext()];
                UIImage *cellImage = UIGraphicsGetImageFromCurrentImageContext();
                UIGraphicsEndImageContext();

                _draggingView = [[UIImageView alloc] initWithImage:cellImage];
            }
            
            [_tableView addSubview:_draggingView];
            CGRect rect = [_tableView rectForRowAtIndexPath:indexPath];
            _draggingView.frame = CGRectOffset(_draggingView.bounds, rect.origin.x, rect.origin.y);
            
            // add a show animation
            [UIView beginAnimations:@"show" context:nil];
            if ([(id)_tableView.lprDelegate respondsToSelector:@selector(tableView:showDraggingView:atIndexPath:)]) {
                [_tableView.lprDelegate tableView:_tableView showDraggingView:_draggingView atIndexPath:indexPath];
            } else {
                // add drop shadow to image and lower opacity
                _draggingView.layer.masksToBounds = NO;
                _draggingView.layer.shadowColor = [[UIColor blackColor] CGColor];
                _draggingView.layer.shadowOffset = CGSizeMake(0, 0);
                _draggingView.layer.shadowRadius = 2.0;
                _draggingView.layer.shadowOpacity = 0.5;
                _draggingView.layer.opacity = self.draggingViewOpacity;
                
                _draggingView.transform = CGAffineTransformMakeScale(1, 1);
                _draggingView.center = CGPointMake(_tableView.center.x, location.y);
            }
            [UIView commitAnimations];
        }
        
        cell.hidden = YES;
        
        self.currentLocationIndexPath = indexPath;
        self.initialIndexPath = indexPath;
        
        // enable scrolling for cell
        self.scrollDisplayLink = [CADisplayLink displayLinkWithTarget:self selector:@selector(scrollTableWithCell:)];
        [self.scrollDisplayLink addToRunLoop:[NSRunLoop mainRunLoop] forMode:NSDefaultRunLoopMode];        
    }
    // dragging
    else if (gesture.state == UIGestureRecognizerStateChanged) {
        // update position of the drag view
        // don't let it go past the top or the bottom too far
        if (location.y >= 0 && location.y <= _tableView.contentSize.height + 50) {
            _draggingView.center = CGPointMake(_tableView.center.x, location.y);
        }
        
        CGRect rect = _tableView.bounds;
        // adjust rect for content inset as we will use it below for calculating scroll zones
        rect.size.height -= _tableView.contentInset.top;
        CGPoint location = [gesture locationInView:_tableView];
        
        [self updateCurrentLocation:gesture];
        
        // tell us if we should scroll and which direction
        CGFloat scrollZoneHeight = rect.size.height / 6;
        CGFloat bottomScrollBeginning = _tableView.contentOffset.y + _tableView.contentInset.top + rect.size.height - scrollZoneHeight;
        CGFloat topScrollBeginning = _tableView.contentOffset.y + _tableView.contentInset.top  + scrollZoneHeight;
        // we're in the bottom zone
        if (location.y >= bottomScrollBeginning) {
            _scrollRate = (location.y - bottomScrollBeginning) / scrollZoneHeight;
        }
        // we're in the top zone
        else if (location.y <= topScrollBeginning) {
            _scrollRate = (location.y - topScrollBeginning) / scrollZoneHeight;
        }
        else {
            _scrollRate = 0;
        }
    }
    // dropped
    else if (gesture.state == UIGestureRecognizerStateEnded) {
        
        NSIndexPath *indexPath = self.currentLocationIndexPath;
        
        // remove scrolling CADisplayLink
        [_scrollDisplayLink invalidate];
        _scrollDisplayLink = nil;
        _scrollRate = 0;
        
        // animate the drag view to the newly hovered cell
        [UIView animateWithDuration:0.3
                         animations:^{
                             if ([(id)_tableView.lprDelegate respondsToSelector:@selector(tableView:hideDraggingView:atIndexPath:)]) {
                                 [_tableView.lprDelegate tableView:_tableView hideDraggingView:_draggingView atIndexPath:indexPath];
                             } else {
                                 CGRect rect = [_tableView rectForRowAtIndexPath:indexPath];
                                 _draggingView.transform = CGAffineTransformIdentity;
                                 _draggingView.frame = CGRectOffset(_draggingView.bounds, rect.origin.x, rect.origin.y);
                             }
                         } completion:^(BOOL finished) {
                             [_tableView beginUpdates];
                             [_tableView deleteRowsAtIndexPaths:[NSArray arrayWithObject:indexPath] withRowAnimation:UITableViewRowAnimationNone];
                             [_tableView insertRowsAtIndexPaths:[NSArray arrayWithObject:indexPath] withRowAnimation:UITableViewRowAnimationNone];
                             [_tableView endUpdates];
                             
                             [_draggingView removeFromSuperview];
                             
                             // reload the rows that were affected just to be safe
                             NSMutableArray *visibleRows = [[_tableView indexPathsForVisibleRows] mutableCopy];
                             [visibleRows removeObject:indexPath];
                             [_tableView reloadRowsAtIndexPaths:visibleRows withRowAnimation:UITableViewRowAnimationNone];
                             
                             _currentLocationIndexPath = nil;
                             _draggingView = nil;
                         }];
    }
}


- (void)updateCurrentLocation:(UILongPressGestureRecognizer *)gesture {
    
    NSIndexPath *indexPath  = nil;
    CGPoint location = CGPointZero;
    
    // refresh index path
    location  = [gesture locationInView:_tableView];
    indexPath = [_tableView indexPathForRowAtPoint:location];
    
    if ([_tableView.delegate respondsToSelector:@selector(tableView:targetIndexPathForMoveFromRowAtIndexPath:toProposedIndexPath:)]) {
        indexPath = [_tableView.delegate tableView:_tableView targetIndexPathForMoveFromRowAtIndexPath:self.initialIndexPath toProposedIndexPath:indexPath];
    }
    
    NSInteger oldHeight = [_tableView rectForRowAtIndexPath:self.currentLocationIndexPath].size.height;
    NSInteger newHeight = [_tableView rectForRowAtIndexPath:indexPath].size.height;
    
    if (indexPath && ![indexPath isEqual:self.currentLocationIndexPath] && [gesture locationInView:[_tableView cellForRowAtIndexPath:indexPath]].y > newHeight - oldHeight) {
        [_tableView beginUpdates];
        [_tableView moveRowAtIndexPath:self.currentLocationIndexPath toIndexPath:indexPath];
        
        if ([(id)_tableView.dataSource respondsToSelector:@selector(tableView:moveRowAtIndexPath:toIndexPath:)]) {
            [_tableView.dataSource tableView:_tableView moveRowAtIndexPath:self.currentLocationIndexPath toIndexPath:indexPath];
        }
        else {
            NSLog(@"moveRowAtIndexPath:toIndexPath: is not implemented");
        }
        
        _currentLocationIndexPath = indexPath;
        [_tableView endUpdates];
    }
}

- (void)scrollTableWithCell:(NSTimer *)timer {    
    UILongPressGestureRecognizer *gesture = _longPress;
    CGPoint location  = [gesture locationInView:_tableView];
    
    CGPoint currentOffset = _tableView.contentOffset;
    CGPoint newOffset = CGPointMake(currentOffset.x, currentOffset.y + self.scrollRate * 10);
    
    if (newOffset.y < -_tableView.contentInset.top) {
        newOffset.y = -_tableView.contentInset.top;
    } else if (_tableView.contentSize.height + _tableView.contentInset.bottom < _tableView.frame.size.height) {
        newOffset = currentOffset;
    } else if (newOffset.y > (_tableView.contentSize.height + _tableView.contentInset.bottom) - _tableView.frame.size.height) {
        newOffset.y = (_tableView.contentSize.height + _tableView.contentInset.bottom) - _tableView.frame.size.height;
    }
    
    [_tableView setContentOffset:newOffset];
    
    if (location.y >= 0 && location.y <= _tableView.contentSize.height + 50) {
        _draggingView.center = CGPointMake(_tableView.center.x, location.y);
    }
    
    [self updateCurrentLocation:gesture];
}

- (void)cancelGesture {
    _longPress.enabled = NO;
    _longPress.enabled = YES;
}

@end


@implementation UITableView (LongPressReorder)

static void *LPRDelegateKey = &LPRDelegateKey;

- (void)setLprDelegate:(id<LPRTableViewDelegate>)LPRDelegate {
    id delegate = objc_getAssociatedObject(self, LPRDelegateKey);
    if (delegate != LPRDelegate) {
        objc_setAssociatedObject(self, LPRDelegateKey, LPRDelegate, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
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

@end