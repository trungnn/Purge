//
//  PurgeAppDelegate.m
//  Purge
//
//  Created by Nguyen Ngoc Trung on 25/2/13.
//  Copyright (c) 2013 Ngoc Trung Nguyen. All rights reserved.
//

#import "PurgeAppDelegate.h"
#import <sys/sysctl.h>
#import <mach/host_info.h>
#import <mach/mach_host.h>
#import <mach/task_info.h>
#import <mach/task.h>

@implementation PurgeAppDelegate

- (NSMutableArray *)memoryHistoryArray {
    if (!_memoryHistoryArray) {
        _memoryHistoryArray = [NSMutableArray array];
    }
    return _memoryHistoryArray;
}

- (void)applicationDidFinishLaunching:(NSNotification *)aNotification
{
    // Insert code here to initialize your application
    [self updateMenuBarText];
    [self purgeMemory];
    
    [NSTimer scheduledTimerWithTimeInterval:10*60.0f target:self selector:@selector(purgeMemory) userInfo:nil repeats:YES];
    [NSTimer scheduledTimerWithTimeInterval:1.0f target:self selector:@selector(updateMenuBarText) userInfo:nil repeats:YES];
}

- (void)updateMenuBarText {
    int mib[6];
    mib[0] = CTL_HW;
    mib[1] = HW_PAGESIZE;
    
    int pagesize;
    size_t length;
    length = sizeof (pagesize);
    if (sysctl (mib, 2, &pagesize, &length, NULL, 0) < 0)
    {
        fprintf (stderr, "getting page size");
    }
    
    mach_msg_type_number_t count = HOST_VM_INFO_COUNT;
    
    vm_statistics_data_t vmstat;
    if (host_statistics (mach_host_self (), HOST_VM_INFO, (host_info_t) &vmstat, &count) != KERN_SUCCESS)
    {
        fprintf (stderr, "Failed to get VM statistics.");
    }
    
//    double total = vmstat.wire_count + vmstat.active_count + vmstat.inactive_count + vmstat.free_count;
//    double wired = vmstat.wire_count / total;
//    double active = vmstat.active_count / total;
//    double inactive = vmstat.inactive_count / total;
//    double free = vmstat.free_count / total;
    
    task_basic_info_64_data_t info;
    unsigned size = sizeof (info);
    task_info (mach_task_self (), TASK_BASIC_INFO_64, (task_info_t) &info, &size);
    
    int gb = 1024*1024*1024;
    
    self.statusItem.title = [NSString stringWithFormat:@"Free: %.2f", (double)vmstat.free_count * pagesize/gb];
}

- (void)purgeMemory {
    NSTask *task;
    task = [[NSTask alloc] init];
    [task setLaunchPath: @"/usr/bin/purge"];
    
    NSPipe *pipe;
    pipe = [NSPipe pipe];
    [task setStandardOutput: pipe];
    
    NSFileHandle *file;
    file = [pipe fileHandleForReading];
    
    [task launch];
    
    NSData *data;
    data = [file readDataToEndOfFile];
    
    NSString *string;
    string = [[NSString alloc] initWithData: data encoding: NSUTF8StringEncoding];
    NSLog (@"grep returned:\n%@", string);

}

- (IBAction)purgeNowPressed:(id)sender {
    [self purgeMemory];
}

- (void)awakeFromNib {
    self.statusItem = [[NSStatusBar systemStatusBar] statusItemWithLength:NSVariableStatusItemLength];
    [self.statusItem setMenu:self.statusMenu];
    [self.statusItem setTitle:@"Status"];
    [self.statusItem setHighlightMode:YES];
}

@end
