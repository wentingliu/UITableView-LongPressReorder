//
//  UITableView+LongPressReorder.h
//
//  Copyright (c) 2013 wtl.
//


#import <UIKit/UIKit.h>

@protocol LPRTableViewDelegate

@optional

// Provide the placeholder view for dragging.
- (UIView *)tableView:(UITableView *)tableView draggingViewForCellAtIndexPath:(NSIndexPath *)indexPath;

// Called within an animation block when the dragging view is about to show.
- (void)tableView:(UITableView *)tableView showDraggingView:(UIView *)view atIndexPath:(NSIndexPath *)indexPath;

// Called within an animation block when the dragging view is about to hide.
- (void)tableView:(UITableView *)tableView hideDraggingView:(UIView *)view atIndexPath:(NSIndexPath *)indexPath;

@end


@interface UITableView (LongPressReorder)

@property (nonatomic, assign, getter = isLongPressReorderEnabled) BOOL longPressReorderEnabled;
@property (nonatomic, assign) id <LPRTableViewDelegate> lprDelegate;


// Use to enable using Custom Cell
@property (nonatomic, assign, getter = isLongPressReorderEnabled) BOOL useCustomCell;

@end

