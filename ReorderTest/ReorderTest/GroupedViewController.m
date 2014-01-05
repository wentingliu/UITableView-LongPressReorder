//
//  GroupedViewController.m
//  ReorderTest
//
//  Created by Benjamin Vogelzang on 4/3/13.
//  Copyright (c) 2013 Ben Vogelzang. All rights reserved.
//

#import "GroupedViewController.h"

#import "UITableView+LongPressReorder.h"

@interface GroupedViewController ()
@property (nonatomic, strong) NSMutableArray *data;
@end

@implementation GroupedViewController

@synthesize data;

- (void)viewDidLoad
{
    [super viewDidLoad];

    NSMutableArray *section1 = [NSMutableArray arrayWithArray:@[@"1", @"2", @"3"]];
    NSMutableArray *section2 = [NSMutableArray arrayWithArray:@[@"4", @"5", @"6"]];
    NSMutableArray *section3 = [NSMutableArray arrayWithArray:@[@"7", @"8", @"9"]];
    data = [NSMutableArray arrayWithArray:@[section1, section2, section3]];
    
    [self.tableView setLongPressReorderEnabled:YES];
    [self.tableView setLprDelegate:(id)self];
}

- (void)didReceiveMemoryWarning
{
    [super didReceiveMemoryWarning];
    // Dispose of any resources that can be recreated.
}

#pragma mark - Table view data source

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView
{
    // Return the number of sections.
    return [data count];
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section
{
    NSArray *array = [data objectAtIndex:section];
    // Return the number of rows in the section.
    return [array count];
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath
{
    static NSString *CellIdentifier = @"Cell";
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:CellIdentifier forIndexPath:indexPath];
    
    // Configure the cell...
    NSArray *array = [data objectAtIndex:indexPath.section];
    cell.textLabel.text = [array objectAtIndex:indexPath.row];
//    cell.hidden = YES;
    
    return cell;
}

#pragma mark - Table view delegate

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath
{
    [self.tableView deselectRowAtIndexPath:indexPath animated:YES];
}

- (void)tableView:(UITableView *)tableView moveRowAtIndexPath:(NSIndexPath *)sourceIndexPath toIndexPath:(NSIndexPath *)destinationIndexPath {
    NSMutableArray *section = (NSMutableArray *)[data objectAtIndex:sourceIndexPath.section];
    id object = [section objectAtIndex:sourceIndexPath.row];
    [section removeObjectAtIndex:sourceIndexPath.row];
    
    NSMutableArray *newSection = (NSMutableArray *)[data objectAtIndex:destinationIndexPath.section];
    [newSection insertObject:object atIndex:destinationIndexPath.row];
}

@end
