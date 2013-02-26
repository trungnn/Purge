//
//  PurgeAppDelegate.h
//  Purge
//
//  Created by Nguyen Ngoc Trung on 25/2/13.
//  Copyright (c) 2013 Ngoc Trung Nguyen. All rights reserved.
//

#import <Cocoa/Cocoa.h>

@interface PurgeAppDelegate : NSObject <NSApplicationDelegate>

@property (nonatomic, strong) NSStatusItem *statusItem;
@property (weak) IBOutlet NSMenu *statusMenu;
@property (nonatomic, strong) NSMutableArray *memoryHistoryArray;
@end
