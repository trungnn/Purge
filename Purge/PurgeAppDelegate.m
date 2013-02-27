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
#import <QuartzCore/QuartzCore.h>

#include <sys/sysctl.h>
#include <sys/types.h>
#include <mach/mach.h>
#include <mach/processor_info.h>
#include <mach/mach_host.h>

processor_info_array_t cpuInfo, prevCpuInfo;
mach_msg_type_number_t numCpuInfo, numPrevCpuInfo;
unsigned numCPUs;
NSLock *CPUUsageLock;

@interface PurgeAppDelegate () <NSMenuDelegate>
@property (nonatomic, strong) CALayer *blueLayer;
@end

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
    [self updateMemoryText];
    [self updateCPUText];
    [self purgeMemory];
    
    int mib[2U] = { CTL_HW, HW_NCPU };
    size_t sizeOfNumCPUs = sizeof(numCPUs);
    int status = sysctl(mib, 2U, &numCPUs, &sizeOfNumCPUs, NULL, 0U);
    if(status)
        numCPUs = 1;
    
    CPUUsageLock = [[NSLock alloc] init];
    
    [NSTimer scheduledTimerWithTimeInterval:1.0f
                                     target:self
                                   selector:@selector(updateCPUText)
                                   userInfo:nil
                                    repeats:YES];
    
    [NSTimer scheduledTimerWithTimeInterval:10*60.0f
                                     target:self
                                   selector:@selector(purgeMemory)
                                   userInfo:nil
                                    repeats:YES];
    
    [NSTimer scheduledTimerWithTimeInterval:1.0f
                                     target:self
                                   selector:@selector(updateMemoryText)
                                   userInfo:nil
                                    repeats:YES];
}

- (void)updateCPUText {
    natural_t numCPUsU = 0U;
    kern_return_t err = host_processor_info(mach_host_self(), PROCESSOR_CPU_LOAD_INFO, &numCPUsU, &cpuInfo, &numCpuInfo);
    if(err == KERN_SUCCESS) {
        [CPUUsageLock lock];
        
        float final_inuse = 0.0;
        float final_total = 0.0;
        
        for(unsigned i = 0U; i < numCPUs; ++i) {
            float inUse, total;
            if(prevCpuInfo) {
                inUse = (
                         (cpuInfo[(CPU_STATE_MAX * i) + CPU_STATE_USER]   - prevCpuInfo[(CPU_STATE_MAX * i) + CPU_STATE_USER])
                         + (cpuInfo[(CPU_STATE_MAX * i) + CPU_STATE_SYSTEM] - prevCpuInfo[(CPU_STATE_MAX * i) + CPU_STATE_SYSTEM])
                         + (cpuInfo[(CPU_STATE_MAX * i) + CPU_STATE_NICE]   - prevCpuInfo[(CPU_STATE_MAX * i) + CPU_STATE_NICE])
                         );
                total = inUse + (cpuInfo[(CPU_STATE_MAX * i) + CPU_STATE_IDLE] - prevCpuInfo[(CPU_STATE_MAX * i) + CPU_STATE_IDLE]);
            } else {
                inUse = cpuInfo[(CPU_STATE_MAX * i) + CPU_STATE_USER] + cpuInfo[(CPU_STATE_MAX * i) + CPU_STATE_SYSTEM] + cpuInfo[(CPU_STATE_MAX * i) + CPU_STATE_NICE];
                total = inUse + cpuInfo[(CPU_STATE_MAX * i) + CPU_STATE_IDLE];
            }
            
            final_inuse += inUse;
            final_total += total;
        }
        
        self.topTextView.string = [NSString stringWithFormat:@"CPU: %.0f%%", (1 - final_inuse/final_total) * 100];
        [self.topTextView alignRight:nil];
        
        [CPUUsageLock unlock];
        
        if(prevCpuInfo) {
            size_t prevCpuInfoSize = sizeof(integer_t) * numPrevCpuInfo;
            vm_deallocate(mach_task_self(), (vm_address_t)prevCpuInfo, prevCpuInfoSize);
        }
        
        prevCpuInfo = cpuInfo;
        numPrevCpuInfo = numCpuInfo;
        
        cpuInfo = NULL;
        numCpuInfo = 0U;
    } else {
        NSLog(@"Error!");
        [NSApp terminate:nil];
    }
}

- (void)updateMemoryText {
    
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
    
//    self.topTextView.string = [NSString stringWithFormat:@"F:%.2f", (double)vmstat.free_count * pagesize/gb];
    self.bottomTextView.string = [NSString stringWithFormat:@"F: %.2fGB", (double)vmstat.free_count * pagesize/gb];
    [self.bottomTextView alignRight:nil];
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
    [self.statusItem setView:[self getView]];
    [self.statusItem setMenu:self.statusMenu];
    [self.statusItem setTitle:@"Status"];
    [self.statusItem setHighlightMode:YES];
    
    self.statusMenu.delegate = self;
}

- (NSView *)getView {
    CGFloat height = [NSStatusBar systemStatusBar].thickness;
    CGFloat width = 60;
    self.statusMenuBackgroundView = [[NSView alloc] initWithFrame:NSRectFromCGRect(CGRectMake(0, 0, width, height))];
    self.blueLayer = [CALayer layer];
    [self.blueLayer setBackgroundColor:CGColorCreateGenericRGB(0.0, 0.0, 0.0, 0.0)];
    [self.statusMenuBackgroundView setWantsLayer:YES]; // view's backing store is using a Core Animation Layer
    [self.statusMenuBackgroundView setLayer:self.blueLayer];
    
    self.bottomTextView = [[NSTextView alloc] initWithFrame:NSRectFromCGRect(CGRectMake(0, 0, width, height/2))];
    self.topTextView = [[NSTextView alloc] initWithFrame:NSRectFromCGRect(CGRectMake(0, height/2, width, height/2))];
    self.topTextView.backgroundColor = [NSColor clearColor];
    self.bottomTextView.backgroundColor = [NSColor clearColor];
    self.topTextView.font = [NSFont boldSystemFontOfSize:9.0];
    self.bottomTextView.font = [NSFont boldSystemFontOfSize:9.0];
    self.topTextView.string = @"";
    self.bottomTextView.string = @"";
    [self.statusMenuBackgroundView addSubview:self.topTextView];
    [self.statusMenuBackgroundView addSubview:self.bottomTextView];
    
    NSButton *button = [[NSButton alloc] initWithFrame:self.statusMenuBackgroundView.frame];
    [button setTarget:self];
    [button setAction:@selector(buttonPressed:)];
    button.alphaValue = 0.0f;
    [self.statusMenuBackgroundView addSubview:button];
    
    return self.statusMenuBackgroundView;
}

- (void)buttonPressed:(id)sender {
    [self.statusItem popUpStatusItemMenu:self.statusMenu];
}

# pragma mark NSMenuDelegate
- (void)menuDidClose:(NSMenu *)menu {
    self.blueLayer.backgroundColor = CGColorCreateGenericRGB(0.0, 0.0, 0.0, 0.0);
    self.topTextView.textColor = [NSColor blackColor];
    self.bottomTextView.textColor = [NSColor blackColor];
}

- (void)menuWillOpen:(NSMenu *)menu {
    self.blueLayer.backgroundColor = CGColorCreateGenericRGB(33.0/255, 66.0/255, 1.0, 1.0);
    self.topTextView.textColor = [NSColor whiteColor];
    self.bottomTextView.textColor = [NSColor whiteColor];
}

@end
