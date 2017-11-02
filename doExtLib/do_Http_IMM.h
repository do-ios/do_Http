//
//  do_Http_MM.h
//  DoExt_MM
//
//  Created by @userName on @time.
//  Copyright (c) 2015年 DoExt. All rights reserved.
//

#import <Foundation/Foundation.h>

@protocol do_Http_IMM <NSObject>
//实现同步或异步方法，parms中包含了所需用的属性
- (void)download:(NSArray *)parms;
- (void)download1:(NSArray *)parms;
- (void)form:(NSArray *)parms;
- (void)getResponseHeader:(NSArray *)parms;
- (void)request:(NSArray *)parms;
- (void)setRequestHeader:(NSArray *)parms;
- (void)upload:(NSArray *)parms;
- (void)stopDownload:(NSArray *)parms;
- (void)setRedirect:(NSArray *)parms;

@end
