//
//  Do_Http_MM.m
//  DoExt_MM
//
//  Created by @userName on @time.
//  Copyright (c) 2015年 DoExt. All rights reserved.
//

#import "do_Http_MM.h"

#import "doScriptEngineHelper.h"
#import "doIScriptEngine.h"
#import "doInvokeResult.h"

#import "doUIModuleHelper.h"
#import "doIOHelper.h"
#import "doIDataSource.h"
#import "doIPage.h"
#import "doJsonHelper.h"
#import "doISourceFS.h"
#import "doIDataFS.h"
#import "doIOHelper.h"
#import "doUIModuleHelper.h"
#import "doServiceContainer.h"
#import "doILogEngine.h"

@interface do_Http_MM()<NSURLConnectionDataDelegate,NSURLSessionDownloadDelegate>

@property (nonatomic, strong) NSDictionary *cookieDict;
@property (nonatomic ,strong) NSMutableDictionary *getCookieDict;
@property (nonatomic ,strong) NSMutableDictionary *setCookieDict;
@property (nonatomic ,strong) NSOutputStream *stream;
@property (nonatomic, strong) NSString *fileNameUploadToServer;
@end

@implementation do_Http_MM
{
    NSURLConnection *_connection;
    NSMutableData *_data;
    doInvokeResult *_invokeResult;
    // upload
    NSURLConnection *_upConnection;
    NSURLConnection *_formConnection;
    NSInteger _upLong;
    
    // download
    NSURLConnection *_downConnection;
    NSString *_downFilePath;
    long long _downLong;
    //下载数据
    NSMutableData *_downData;
    NSInteger _statusCode;
    //重定向
    BOOL _isRedirect;
    NSMutableArray *fileSizeArray;
    
    NSMutableDictionary *taskDict;//断点下载相关保存
    NSMutableDictionary *taskIdDict;//
    NSMutableDictionary *taskResumeDataDict;
    NSMutableDictionary *taskPathDict;
}

#pragma mark - 注册属性（--属性定义--）
/*
 [self RegistProperty:[[doProperty alloc]init:@"属性名" :属性类型 :@"默认值" : BOOL:是否支持代码修改属性]];
 */
-(void)OnInit
{
    [super OnInit];
    //注册属性
    
    [self RegistProperty:[[doProperty alloc] init:@"method" :String :@"get" :NO]];
    [self RegistProperty:[[doProperty alloc] init:@"url" :String :@"" :NO]];
    [self RegistProperty:[[doProperty alloc] init:@"timeout" :Number :@"5000" :NO]];
    [self RegistProperty:[[doProperty alloc] init:@"contentType" :String :@"text/html" :NO]];
    [self RegistProperty:[[doProperty alloc] init:@"body" :String :@"" :NO]];
    [self RegistProperty:[[doProperty alloc]init:@"responseEncoding" :String :@"utf-8" :NO]];
    self.getCookieDict = [NSMutableDictionary dictionary];
    self.setCookieDict = [NSMutableDictionary dictionary];
    
    _isRedirect = YES;
    
    taskDict = [NSMutableDictionary dictionary];
    taskIdDict = [NSMutableDictionary dictionary];
    taskResumeDataDict = [NSMutableDictionary dictionary];
    taskPathDict = [NSMutableDictionary dictionary];
    self.fileNameUploadToServer = @"";
}

//销毁所有的全局对象
-(void)Dispose
{
    [_connection cancel];
    _connection = nil;
    _downData = nil;
    _invokeResult = nil;
    
    [_downConnection cancel];
    _downConnection = nil;
    _downData = nil;
    
    [_upConnection cancel];
    _upConnection = nil;
    
    self.fileNameUploadToServer = nil;
    //自定义的全局属性
    [super Dispose];
}

#pragma mark -
#pragma mark - 同步异步方法的实现
- (void)setRedirect:(NSArray *)parms
{
    NSDictionary *_dictParas = [parms objectAtIndex:0];
    //参数字典_dictParas
//    id<doIScriptEngine> _scritEngine = [parms objectAtIndex:1];
//    //自己的代码实现
//    
//    doInvokeResult *_invokeResult = [parms objectAtIndex:2];
//    //_invokeResult设置返回值
    _isRedirect = [doJsonHelper GetOneBoolean:_dictParas :@"isSetRedirect" :YES];
}

- (void)form:(NSArray *)parms
{
    NSDictionary *_dictParas = [parms objectAtIndex:0];
    //自己的代码实现
    NSDictionary *dataDict = [doJsonHelper GetOneNode:_dictParas :@"data"];
    NSArray *files = [dataDict objectForKey:@"files"];
    NSArray *texts = [dataDict objectForKey:@"texts"];
    NSString *timeout = [self GetPropertyValue:@"timeout"];
    NSString *urlStr = [self GetPropertyValue:@"url"];
    NSMutableURLRequest *requestM = [NSMutableURLRequest requestWithURL:[NSURL URLWithString:urlStr] cachePolicy:0 timeoutInterval:[timeout floatValue]/1000];
    fileSizeArray = [NSMutableArray array];
    // 1> 设定HTTP请求方式
    NSString *method = [self GetPropertyValue:@"method"];
    if([method compare:@"put" options:NSCaseInsensitiveSearch] == NSOrderedSame)
    {
        requestM.HTTPMethod = @"PUT";
    }
    else
    {
        requestM.HTTPMethod = @"POST";
    }
    //2> 设置请求body
    NSMutableString *bodyStr = [[NSMutableString alloc]init];
    NSMutableData *dataM = [NSMutableData data];
    NSString* BoundaryConstant = [doUIModuleHelper stringWithUUID];
    if (texts && texts.count > 0)
    {
        NSDictionary *paramDict = [self uploadFormWithArray:texts];
        NSArray *allKeys = paramDict.allKeys;
        for (NSString *keyStr in allKeys) {
            //添加分割线  换行
            [bodyStr appendFormat:@"--%@\r\n",BoundaryConstant];
            //添加字段名称  换2行
            [bodyStr appendFormat:@"Content-Disposition: form-data; name=\"%@\"\r\n\r\n",keyStr];
            [bodyStr appendFormat:@"%@\r\n",[paramDict objectForKey:keyStr]];
        }
    }
    if (!files|| files.count == 0) {
        [bodyStr appendFormat:@"--%@--\r\n",BoundaryConstant];
        [dataM appendData:[bodyStr dataUsingEncoding:NSUTF8StringEncoding]];

    }
    else
    {
        //循环遍历所有文件
        NSDictionary *paramDict = [self uploadFormWithArray:files];
        NSArray *allKeys = paramDict.allKeys;
        [dataM appendData:[bodyStr dataUsingEncoding:NSUTF8StringEncoding]];
        NSInteger dataLength = dataM.length;
        NSString *filePath;
        @try {
            for (NSString *keyStr in allKeys) {
                filePath = [doIOHelper GetLocalFileFullPath:self.CurrentPage.CurrentApp : [paramDict objectForKey:keyStr]];
                if (![[NSFileManager defaultManager]fileExistsAtPath:filePath]) {
                    NSException *exc = [[NSException alloc]initWithName:@"do_Http" reason:[NSString stringWithFormat:@"%@文件不存在",[paramDict objectForKey:keyStr]] userInfo:nil];
                    [[doServiceContainer Instance].LogEngine WriteError:exc :[NSString stringWithFormat:@"%@文件不存在",[paramDict objectForKey:keyStr]]];
                    continue;
                }
                // 0. 获取上传文件的mimeType
                NSString *mimeType = [self mimeTypeWithFilePath:filePath];
                if (!mimeType) return;
                
                // 1. 拼接要上传的数据体
                [dataM appendData:[[self topStringWithMimeType:mimeType uploadFile:filePath withUpName:keyStr withBoundaryStr:BoundaryConstant withRandomIDStr:@""] dataUsingEncoding:NSUTF8StringEncoding]];
                // 拼接上传文件本身的二进制数据
                NSData *fileData = [NSData dataWithContentsOfFile:filePath];
                [fileSizeArray insertObject:@(fileData.length) atIndex:0];
                NSLog(@"fileLength = %ld",(unsigned long)fileData.length);
                [dataM appendData:fileData];
                [dataM appendData:[@"\r\n" dataUsingEncoding:NSUTF8StringEncoding]];
            }
        }
        @catch (NSException *exception) {
            [[doServiceContainer Instance].LogEngine WriteError:exception :exception.debugDescription];
        }
        if (dataM.length > dataLength) {
            [dataM appendData:[[self bottomString:BoundaryConstant withRandomIDStr:@""] dataUsingEncoding:NSUTF8StringEncoding]];
        }
    }
    
    // 2> 设置数据体
    requestM.HTTPBody = dataM;
    // 3> 指定Content-Type
    NSString *typeStr = [NSString stringWithFormat:@"multipart/form-data; boundary=%@", BoundaryConstant];
    [requestM setValue:typeStr forHTTPHeaderField:@"Content-Type"];
    // 4> 指定数据长度
    _upLong = dataM.length;
    NSString *lengthStr = [NSString stringWithFormat:@"%@", @([dataM length])];
    [requestM setValue:lengthStr forHTTPHeaderField:@"Content-Length"];
    //设置header
    if (self.setCookieDict.allKeys.count > 0) {
        [requestM setHTTPShouldHandleCookies:YES];
        for (NSString *key in self.setCookieDict.allKeys) {
            if ([key isEqualToString:@"Cookie"]) {
                continue;
            }
            [requestM setValue:self.setCookieDict[key] forHTTPHeaderField:key];
        }
    }
    _formConnection = [[NSURLConnection alloc] initWithRequest:requestM delegate:self startImmediately:YES];
}
- (NSDictionary *)uploadFormWithArray:(NSArray *)array
{
    NSMutableDictionary *paramDict = [NSMutableDictionary dictionary];
    for (NSDictionary *textDict in array) {
        [paramDict setObject:[textDict objectForKey:@"value"] forKey:[textDict objectForKey:@"key"]];
    }
    return paramDict;
}


//upload是同步方法
- (void)upload:(NSArray *)parms {
    NSDictionary * _dicParas = [parms objectAtIndex:0];
    _invokeResult = [parms objectAtIndex:2];
    NSString *path = [doJsonHelper GetOneText:_dicParas :@"path" :nil];
    NSString *name = [doJsonHelper GetOneText:_dicParas :@"name" :@""];
    self.fileNameUploadToServer = [doJsonHelper GetOneText:_dicParas :@"filename" :@""];
    if (name.length == 0 || !name) {
        name = @"file";
    }
    if(path && path.length>0) {
        if(_upConnection)
            [_upConnection cancel];
        path = [doIOHelper GetLocalFileFullPath:self.CurrentPage.CurrentApp : path];
        
        NSString *urlStr = [self GetPropertyValue:@"url"];
        NSString* BoundaryConstant = [doUIModuleHelper stringWithUUID];
        
        NSURLRequest *request = [self requestForUploadURL:[NSURL URLWithString:urlStr] uploadFileName:name localFilePath:path withBoundaryStr:BoundaryConstant withRandomIDStr:@""];
        _upConnection = [[NSURLConnection alloc] initWithRequest:request delegate:self startImmediately:YES];
    }
}
//拼接顶部字符串
- (NSString *)topStringWithMimeType:(NSString *)mimeType uploadFile:(NSString *) uploadFile withUpName:(NSString *)uploadID  withBoundaryStr:(NSString *)boundaryStr withRandomIDStr:(NSString *)randomIDStr
{
    NSMutableString *strM = [NSMutableString string];
    [strM appendFormat:@"--%@\r\n", boundaryStr];
    [strM appendFormat:@"Content-Disposition: form-data; name=\"%@\"; filename=\"%@\"\r\n", uploadID, ([self.fileNameUploadToServer isEqualToString:@""] ? [uploadFile lastPathComponent] : self.fileNameUploadToServer)];
    [strM appendFormat:@"Content-Type:application/octet-stream\r\n\r\n"];
    return [strM copy];
}
// 拼接底部字符串
- (NSString *)bottomString:(NSString *)boundaryStr withRandomIDStr:(NSString *)randomIDStr
{
    NSMutableString *strM = [NSMutableString string];
    
    //    [strM appendFormat:@"%@%@\n", boundaryStr, randomIDStr];
    //    [strM appendString:@"Content-Disposition: form-data; name=\"submit\"\n\n"];
    //    [strM appendString:@"Submit\n"];
    [strM appendFormat:@"\r\n--%@--", boundaryStr];
    return [strM copy];
}

/** 指定全路径文件的mimeType */
- (NSString *)mimeTypeWithFilePath:(NSString *)filePath
{
    // 1. 判断文件是否存在
    if (![[NSFileManager defaultManager] fileExistsAtPath:filePath]) {
        return nil;
    }
    
    // 2. 使用HTTP HEAD方法获取上传文件信息
    NSURL *url = [NSURL fileURLWithPath:filePath];
    NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:url];
    
    // 3. 调用同步方法获取文件的MimeType
    NSURLResponse *response = nil;
    [NSURLConnection sendSynchronousRequest:request returningResponse:&response error:NULL];
    
    return response.MIMEType;
}

/** 上传文件网络请求 */
- (NSURLRequest *)requestForUploadURL:(NSURL *)url uploadFileName:(NSString *)fileName localFilePath:(NSString *)filePath withBoundaryStr:(NSString *)boundaryStr withRandomIDStr:(NSString *)randomID
{
    // 0. 获取上传文件的mimeType
    NSString *mimeType = [self mimeTypeWithFilePath:filePath];
    if (!mimeType) return nil;
    
    // 1. 拼接要上传的数据体
    NSMutableData *dataM = [NSMutableData data];
    [dataM appendData:[[self topStringWithMimeType:mimeType uploadFile:filePath withUpName:fileName withBoundaryStr:boundaryStr withRandomIDStr:randomID] dataUsingEncoding:NSUTF8StringEncoding]];
    // 拼接上传文件本身的二进制数据
    [dataM appendData:[NSData dataWithContentsOfFile:filePath]];
    [dataM appendData:[[self bottomString:boundaryStr withRandomIDStr:randomID] dataUsingEncoding:NSUTF8StringEncoding]];
    
    // 2. 设置请求
    NSString *timeout = [self GetPropertyValue:@"timeout"];
    if(!timeout || [timeout isEqualToString:@""])
        timeout = [self GetProperty:@"timeout"].DefaultValue;
    NSMutableURLRequest *requestM = [NSMutableURLRequest requestWithURL:url cachePolicy:0 timeoutInterval:[timeout floatValue]/1000];
    // 1> 设定HTTP请求方式
    NSString *method = [self GetPropertyValue:@"method"];
    if([method compare:@"put" options:NSCaseInsensitiveSearch] == NSOrderedSame)
    {
        requestM.HTTPMethod = @"PUT";
    }
    else
    {
        requestM.HTTPMethod = @"POST";
    }
    // 2> 设置数据体
    requestM.HTTPBody = dataM;
    // 3> 指定Content-Type
    NSString *typeStr = [NSString stringWithFormat:@"multipart/form-data; boundary=%@", boundaryStr];
    [requestM setValue:typeStr forHTTPHeaderField:@"Content-Type"];
    // 4> 指定数据长度
    _upLong = dataM.length;
    NSString *lengthStr = [NSString stringWithFormat:@"%@", @([dataM length])];
    [requestM setValue:lengthStr forHTTPHeaderField:@"Content-Length"];
    //设置header
    if (self.setCookieDict.allKeys.count > 0) {
        [requestM setHTTPShouldHandleCookies:YES];
        for (NSString *key in self.setCookieDict.allKeys) {
            if ([key isEqualToString:@"Cookie"]) {
                continue;
            }
            [requestM setValue:self.setCookieDict[key] forHTTPHeaderField:key];
        }
    }

    return [requestM copy];
}

//download是同步方法
- (void)download:(NSArray *)parms {
    NSDictionary * _dicParas = [parms objectAtIndex:0];
    _invokeResult = [parms objectAtIndex:2];
    _downFilePath = [doJsonHelper GetOneText:_dicParas :@"path" :nil];
    if (self.CurrentPage) {
        _downFilePath = [doIOHelper GetLocalFileFullPath:self.CurrentPage.CurrentApp : _downFilePath];
    }else
        _downFilePath = [doIOHelper GetLocalFileFullPath:self.CurrentApp : _downFilePath];
    if(_downFilePath && _downFilePath.length>0) {
        if(_downConnection)
            [_downConnection cancel];
        NSMutableURLRequest *request = [self getRequest];
        [request setHTTPMethod:@"GET"];
        _downConnection = [[NSURLConnection alloc] initWithRequest:request delegate:self startImmediately:YES];
    }
}
- (void)download1:(NSArray *)parms
{
    NSDictionary *_dictParas = [parms objectAtIndex:0];
    //参数字典_dictParas
    id<doIScriptEngine> _scritEngine = [parms objectAtIndex:1];
    //自己的代码实现
    NSString *path = [doJsonHelper GetOneText:_dictParas :@"path" :@""];
    NSString *taskId = [doJsonHelper GetOneText:_dictParas :@"taskId" :@""];
    NSString *urlStr = [self GetPropertyValue:@"url"];
    
    if (![path hasPrefix:@"data://"]){
        [[doServiceContainer Instance].LogEngine WriteError:nil :@"path仅支持data目录"];
        return;
    }
    path = [doIOHelper GetLocalFileFullPath:_scritEngine.CurrentApp : path];
    if ([path isEqualToString:@""]) {
        [[doServiceContainer Instance].LogEngine WriteError:nil :@"获取本地path路径失败"];
        return;
    }
    NSString *targetDirectory = [path stringByDeletingLastPathComponent];
    if (![doIOHelper ExistDirectory:targetDirectory]) { // path对应的文件目录不存在
        [doIOHelper CreateDirectory:targetDirectory]; // 创建
        if (![doIOHelper ExistDirectory:targetDirectory]) { // 仍不存在,创建失败
            [[doServiceContainer Instance].LogEngine WriteError:nil :@"创建path对应的本地目标下载路径失败"];
            return;
        }
    }
    
    // 得到session对象
    NSURLSessionConfiguration *configuration = [NSURLSessionConfiguration defaultSessionConfiguration] ;
    //默认配置
    NSOperationQueue *operation = [[NSOperationQueue alloc]init];
    operation.maxConcurrentOperationCount = 4;
    NSURLSession *session = [NSURLSession sessionWithConfiguration:configuration delegate:self delegateQueue:operation];
    //创建任务
    NSURLSessionDownloadTask *downloadTask;
    if ([taskDict.allKeys containsObject:taskId]) {
        //暂停
        NSURLSessionDownloadTask *tempTask = [taskDict objectForKey:taskId];
        if (tempTask.state == NSURLSessionTaskStateRunning) {
            [tempTask cancelByProducingResumeData:^(NSData * _Nullable resumeData) {
                [taskResumeDataDict setObject:resumeData forKey:taskId];
            }];
        }
        if ([taskResumeDataDict.allKeys containsObject:taskId]) {
            downloadTask = [session downloadTaskWithResumeData:[taskResumeDataDict objectForKey:taskId]];
        }
        else{
            downloadTask = [session downloadTaskWithURL:[NSURL URLWithString:urlStr]];
        }
    }
    else
    {
        downloadTask = [session downloadTaskWithURL:[NSURL URLWithString:urlStr]];
    }
    [taskPathDict setObject:path forKey:taskId];//保存文件路径
    [taskDict setObject:downloadTask forKey:taskId];//保存下载任务
    [taskIdDict setObject:taskId forKey:[NSString stringWithFormat:@"%p",downloadTask]];//保存id
    //开始任务
    [downloadTask resume];
}
- (void)stopDownload:(NSArray *)parms
{
    NSDictionary *_dictParas = [parms objectAtIndex:0];
    //参数字典_dictParas
//    id<doIScriptEngine> _scritEngine = [parms objectAtIndex:1];
//    //自己的代码实现
//    
//    doInvokeResult *_invokeResult = [parms objectAtIndex:2];
//    //_invokeResult设置返回值
    
    NSString *taskId = [doJsonHelper GetOneText:_dictParas :@"taskId" :@""];
    if ([taskDict.allKeys containsObject:taskId]) {
        NSURLSessionDownloadTask *downTask = [taskDict objectForKey:taskId];
        if (downTask.state == NSURLSessionTaskStateRunning) {
            [downTask cancelByProducingResumeData:^(NSData * _Nullable resumeData) {
                [taskResumeDataDict setObject:resumeData forKey:taskId];//保存下载任务
            }];
        }
    }
}
//request是同步方法
- (void)request:(NSArray *)parms
{
    _invokeResult = [parms objectAtIndex:2];
    [self request];
}
- (void)getResponseHeader:(NSArray *)parms
{
    NSDictionary *_dictParas = [parms objectAtIndex:0];
    doInvokeResult *invokeResult = [parms objectAtIndex:2];
    NSString *propertyKey = [doJsonHelper GetOneText:_dictParas :@"key" :@""];
    if (propertyKey.length == 0 || [propertyKey isEqualToString:@""]) {
        [invokeResult SetResultNode:_getCookieDict];
    }
    NSString *propertyValue;
    if ([[propertyKey lowercaseString] isEqualToString:@"set-cookie"]) {
        NSMutableArray *valuesArray = [NSMutableArray array];
        if ([_getCookieDict objectForKey:@"Set-Cookie"])[valuesArray addObject:[_getCookieDict objectForKey:@"Set-Cookie"]];
        [invokeResult SetResultArray:valuesArray];
    }
    else
    {
        propertyValue = [_getCookieDict objectForKey:propertyKey];
        [invokeResult SetResultText:propertyValue];
    }
}

- (void)setRequestHeader:(NSArray *)parms
{
    NSDictionary *_dictParas = [parms objectAtIndex:0];
    //参数字典_dictParas
    NSString *cookieKey = [doJsonHelper GetOneText:_dictParas :@"key" :@""];
    NSString *cookieValue = [doJsonHelper GetOneText:_dictParas :@"value" :@""];
    if (cookieValue.length == 0) {
        return;
    }
    [self.setCookieDict setObject:cookieValue forKey:cookieKey];
}


#pragma mark private methed
- (doInvokeResult *)getInvokeResult:(long long)currentSize :(long long)totalSize
{
    doInvokeResult *_myInvokeResult = [[doInvokeResult alloc]init:nil];
    NSMutableDictionary *jsonNode = [[NSMutableDictionary alloc] init];
    [jsonNode setObject:[NSNumber numberWithFloat:currentSize*1.0/1024] forKey:@"currentSize" ];
    [jsonNode setObject:[NSNumber numberWithFloat:totalSize*1.0/1024] forKey:@"totalSize" ];
    [_myInvokeResult SetResultNode:jsonNode];
    return _myInvokeResult;
}
- (NSMutableURLRequest *)getRequest
{
    NSString *urlStr = [self GetPropertyValue:@"url"];
    NSLog(@"%@",urlStr);
    NSString *timeout = [self GetPropertyValue:@"timeout"];
    if(!timeout || [timeout isEqualToString:@""])
        timeout = [self GetProperty:@"timeout"].DefaultValue;
    
    //    NSURL *url = [NSURL URLWithString:[urlStr stringByAddingPercentEscapesUsingEncoding:NSUTF8StringEncoding]];
    //这里不转码，由前端js或者lua转码
    NSURL *url = [NSURL URLWithString:urlStr];
    
    NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:url cachePolicy:NSURLRequestReloadIgnoringLocalCacheData timeoutInterval:[timeout floatValue]/1000];
    
    NSString *contentType = [self GetPropertyValue:@"contentType"];
    if(!contentType || [contentType isEqualToString:@""])
        contentType = @"application/x-www-form-urlencoded";
    
    [request setValue:contentType forHTTPHeaderField:@"Content-Type"];
    //设置header
    if (self.setCookieDict.allKeys.count > 0) {
        [request setHTTPShouldHandleCookies:YES];
        for (NSString *key in self.setCookieDict.allKeys) {
            if ([key isEqualToString:@"Cookie"]) {
                continue;
            }
            [request setValue:self.setCookieDict[key] forHTTPHeaderField:key];
        }
    }

    return request;
}

- (void) request
{
    if(_connection)
        [_connection cancel];
    NSMutableURLRequest *request = [self getRequest];
    
    NSString *method = [self GetPropertyValue:@"method"];
    if(!method || [method isEqualToString:@""])
        method = [self GetProperty:@"method"].DefaultValue;
    if([method compare:@"get" options:NSCaseInsensitiveSearch] == NSOrderedSame)
    {
        [request setHTTPMethod:@"GET"];
        _connection = [[NSURLConnection alloc] initWithRequest:request delegate:self startImmediately:YES];
    }
    else if([method compare:@"post" options:NSCaseInsensitiveSearch] == NSOrderedSame)
    {
        NSString *body = [self GetPropertyValue:@"body"];
        [request setHTTPMethod:@"POST"];
        NSMutableData *myRequestData=[NSMutableData data];
        [myRequestData appendData:[body dataUsingEncoding:NSUTF8StringEncoding]];
        NSUInteger dataLong = myRequestData.length;
        [request setValue:[NSString stringWithFormat:@"%lu",( unsigned long)dataLong] forHTTPHeaderField:@"Content-Length"];
        [request setHTTPBody:myRequestData];
        _connection = [[NSURLConnection alloc] initWithRequest:request delegate:self startImmediately:YES];
        
    }
    else if([method compare:@"put" options:NSCaseInsensitiveSearch] == NSOrderedSame)
    {
        NSString *body = [self GetPropertyValue:@"body"];
        [request setHTTPMethod:@"PUT"];
        NSMutableData *myRequestData=[NSMutableData data];
        [myRequestData appendData:[body dataUsingEncoding:NSUTF8StringEncoding]];
        NSUInteger dataLong = myRequestData.length;
        [request setValue:[NSString stringWithFormat:@"%lu",( unsigned long)dataLong] forHTTPHeaderField:@"Content-Length"];
        [request setHTTPBody:myRequestData];
        _connection = [[NSURLConnection alloc] initWithRequest:request delegate:self startImmediately:YES];
    }
    else if([method compare:@"patch" options:NSCaseInsensitiveSearch] == NSOrderedSame)
    {
        NSString *body = [self GetPropertyValue:@"body"];
        [request setHTTPMethod:@"PATCH"];
        NSMutableData *myRequestData=[NSMutableData data];
        [myRequestData appendData:[body dataUsingEncoding:NSUTF8StringEncoding]];
        NSUInteger dataLong = myRequestData.length;
        [request setValue:[NSString stringWithFormat:@"%lu",( unsigned long)dataLong] forHTTPHeaderField:@"Content-Length"];
        [request setHTTPBody:myRequestData];
        _connection = [[NSURLConnection alloc] initWithRequest:request delegate:self startImmediately:YES];
    }
    else if([method compare:@"delete" options:NSCaseInsensitiveSearch] == NSOrderedSame)
    {
//        NSString *body = [self GetPropertyValue:@"body"];
        [request setHTTPMethod:@"DELETE"];
//        NSMutableData *myRequestData=[NSMutableData data];
//        [myRequestData appendData:[body dataUsingEncoding:NSUTF8StringEncoding]];
//        NSUInteger dataLong = myRequestData.length;
//        [request setValue:[NSString stringWithFormat:@"%lu",( unsigned long)dataLong] forHTTPHeaderField:@"Content-Length"];
//        [request setHTTPBody:myRequestData];
        _connection = [[NSURLConnection alloc] initWithRequest:request delegate:self startImmediately:YES];
    }
    else
    {
        [NSException raise:@"do_Http" format:@"请求模式未知!"];
    }
}

#pragma mark - NSURLSessionDownloadDelegate
- (void)URLSession:(NSURLSession *)session downloadTask:(NSURLSessionDownloadTask *)downloadTask didWriteData:(int64_t)bytesWritten totalBytesWritten:(int64_t)totalBytesWritten totalBytesExpectedToWrite:(int64_t)totalBytesExpectedToWrite
{
    NSString *taskId = [taskIdDict objectForKey:[NSString stringWithFormat:@"%p",downloadTask]];
    doInvokeResult *invokeResult = [[doInvokeResult alloc]init:self.UniqueKey];
    NSMutableDictionary *node = [NSMutableDictionary dictionary];
    [node setObject:taskId forKey:@"taskId"];
    [node setObject:@(totalBytesWritten / 1024.0) forKey:@"currentSize"];
    [node setObject:@(totalBytesExpectedToWrite/1024.0) forKey:@"totalSize"];
    [invokeResult SetResultNode:node];
    [self.EventCenter FireEvent:@"progress" :invokeResult];
    NSLog(@"------%f====taskID = %@,///%ld", 1.0 * totalBytesWritten / totalBytesExpectedToWrite,taskId,(unsigned long)downloadTask.taskIdentifier);
}
- (void)URLSession:(NSURLSession *)session downloadTask:(NSURLSessionDownloadTask *)downloadTask
 didResumeAtOffset:(int64_t)fileOffset
expectedTotalBytes:(int64_t)expectedTotalBytes
{
    NSString *taskId = [taskIdDict objectForKey:[NSString stringWithFormat:@"%p",downloadTask]];
    NSLog(@"dfafdaf%f====taskID = %@,///%ld", 1.0 * fileOffset / expectedTotalBytes,taskId,(unsigned long)downloadTask.taskIdentifier);
}
/**
 *  下载完毕会调用一次这个方法
 */
- (void)URLSession:(NSURLSession *)session downloadTask:(NSURLSessionDownloadTask *)downloadTask didFinishDownloadingToURL:(NSURL *)location
{
    NSString *taskId = [taskIdDict objectForKey:[NSString stringWithFormat:@"%p",downloadTask]];
    NSString *filePath = [taskPathDict objectForKey:taskId];
    [taskDict removeObjectForKey:taskId];
    // 剪切location路径下的临时文件到以后文件存放的地址
    NSFileManager *mgr = [NSFileManager defaultManager];
    NSError *error;
    BOOL success = [mgr moveItemAtURL:location toURL:[NSURL fileURLWithPath:filePath] error:&error];
    if (success) {
        doInvokeResult *invokeResult = [[doInvokeResult alloc]init:self.UniqueKey];
        NSMutableDictionary *node = [NSMutableDictionary dictionary];
        [node setObject:taskId forKey:@"taskId"];
        [node setObject:@"200" forKey:@"status"];
        [node setObject:@"success" forKey:@"data"];
        [invokeResult SetResultNode:node];
        [self.EventCenter FireEvent:@"result" :invokeResult];
    }else {
        [[doServiceContainer Instance].LogEngine WriteError:nil :[NSString stringWithFormat:@"下载失败: %@",error.description]];
    }
}
- (void)URLSession:(NSURLSession *)session task:(NSURLSessionTask *)task didCompleteWithError:(NSError *)error
{
    NSString *taskId = [taskIdDict objectForKey:[NSString stringWithFormat:@"%p",task]];
    NSMutableDictionary *jsonNode = [[NSMutableDictionary alloc] init];
    NSMutableDictionary *resultNode = [[NSMutableDictionary alloc]init];
    if (error) {
        if (error.code == -1005 || error.code == -1009) {
            
            [jsonNode setObject:@"408" forKey:@"status"];
            [jsonNode setObject:@"网络离线" forKey:@"message"];
            
            [resultNode setObject:@"408" forKey:@"status"];
            [resultNode setObject:@"网络离线" forKey:@"data"];
            
        }
        else
        {
            [jsonNode setObject:@"400" forKey:@"status"];
            [jsonNode setObject:[error localizedDescription] forKey:@"message"];
            
            [resultNode setObject:@"400" forKey:@"status"];
            [resultNode setObject:@"其他网络错误" forKey:@"data"];
        }
        if ([error.userInfo objectForKey:NSURLSessionDownloadTaskResumeData]) {
            NSData *resumeData = [error.userInfo objectForKey:NSURLSessionDownloadTaskResumeData];
            [taskResumeDataDict setObject:resumeData forKey:taskId];
        }
        [_invokeResult SetResultNode:jsonNode];
        [self.EventCenter FireEvent:@"fail" :_invokeResult];
        [_invokeResult SetResultNode:resultNode];
        [self.EventCenter FireEvent:@"result" :_invokeResult];
    }
    else{
        [taskDict removeObjectForKey:taskId];
    }
}
#pragma mark - connection
//设置证书,在客户端默认忽略证书认证
- (BOOL)connection:(NSURLConnection *)connection canAuthenticateAgainstProtectionSpace:(NSURLProtectionSpace *)protectionSpace
{
    return [protectionSpace.authenticationMethod isEqualToString:NSURLAuthenticationMethodServerTrust];
}
- (void)connection:(NSURLConnection *)connection didReceiveAuthenticationChallenge:(NSURLAuthenticationChallenge *)challenge
{
    if ([challenge.protectionSpace.authenticationMethod isEqualToString:NSURLAuthenticationMethodServerTrust]) {
        [[challenge sender] useCredential:[NSURLCredential credentialForTrust:challenge.protectionSpace.serverTrust] forAuthenticationChallenge:challenge];
    }
}
// 重定向
- (NSURLRequest *)connection:(NSURLConnection *)connection willSendRequest:(NSURLRequest *)request redirectResponse:(nullable NSURLResponse *)response
{
    if (_isRedirect) {
        return request;
    }
    NSHTTPURLResponse *urlResponse = (NSHTTPURLResponse *)response;
    if (urlResponse.statusCode == 302) {
        return nil;
    }
    else
    {
        return request;
    }
}
// connection delegate
- (void)connection:(NSURLConnection *)connection didSendBodyData:(NSInteger)bytesWritten totalBytesWritten:(NSInteger)totalBytesWritten totalBytesExpectedToWrite:(NSInteger)totalBytesExpectedToWrite
{
    if(connection == _upConnection || connection == _downConnection) {
        [self.EventCenter FireEvent:@"progress" :[self getInvokeResult:totalBytesWritten :totalBytesExpectedToWrite]];
    }
    if (connection == _formConnection) {
        if (fileSizeArray.count > 0) {
            NSUInteger index = [self getcurrentFile:totalBytesWritten];
            NSNumber *filesize = [fileSizeArray objectAtIndex:index];
            NSMutableDictionary *node = [NSMutableDictionary dictionary];
            [node setObject:@(totalBytesWritten/1024.0) forKey:@"currentSize"];
            [node setObject:@(totalBytesExpectedToWrite/1024.0) forKey:@"totalSize"];
            [node setObject:@([filesize integerValue]/1024.0) forKey:@"currentFileSize"];
            [node setObject:@(index) forKey:@"index"];
            doInvokeResult *invokeResult = [[doInvokeResult alloc]init:self.UniqueKey];
            [invokeResult SetResultNode:node];
            [self.EventCenter FireEvent:@"progress" :invokeResult];
        }
    }
}
- (NSUInteger)getcurrentFile:(NSInteger)currentSize
{
    NSInteger tempLength = 0;
    for (NSNumber *fileLength in fileSizeArray) {
        if (currentSize >= tempLength && currentSize < (tempLength + fileLength.integerValue))
        {
            return  [fileSizeArray indexOfObject:fileLength];
        }
        else
        {
            tempLength += fileLength.integerValue;
        }
    }
    return fileSizeArray.count - 1;
}
- (void)connection:(NSURLConnection *)connection didReceiveResponse:(NSURLResponse *)response
{
    if(connection == _downConnection) {//下载
        if(!_downData)
            _downData = [NSMutableData new];
        [_downData setLength:0];
        _downLong = response.expectedContentLength;
    }
    if(!_data)
    {
        _data = [NSMutableData new];
    }
    [_data setLength:0];

    NSHTTPURLResponse *httpUrlResponse = (NSHTTPURLResponse*)response;
    _statusCode = httpUrlResponse.statusCode;
    for (NSString *key in httpUrlResponse.allHeaderFields.allKeys) {
        [self.getCookieDict setObject:[httpUrlResponse.allHeaderFields objectForKey:key] forKey:key];
    }
}
- (void)connection:(NSURLConnection *)connection didReceiveData:(NSData *)data
{
    if(connection == _downConnection) {
        [_downData appendData:data];
        [self.EventCenter FireEvent:@"progress" :[self getInvokeResult:_downData.length :_downLong]];
    }
    else{
        [_data appendData:data];
    }
}
- (void)connectionDidFinishLoading:(NSURLConnection *)connection
{
    doInvokeResult *invokeResult = [doInvokeResult new];
    if (connection == _downConnection) {
        NSFileManager *fileMag = [NSFileManager defaultManager];
        [fileMag createDirectoryAtPath:[_downFilePath stringByDeletingLastPathComponent] withIntermediateDirectories:YES attributes:nil error:nil];
        [_downData writeToFile:_downFilePath atomically:YES];
    }
    else if(connection == _upConnection)
    {
    }
    if (_statusCode == 200)
    {
        //拿到属性
        NSString *encode = [self GetPropertyValue:@"responseEncoding"];
        if ([encode isEqualToString:@""]) {
            encode = [self GetProperty:@"responseEncoding"].DefaultValue;
        }
        NSStringEncoding encoding;
        if ([encode.lowercaseString isEqualToString:@"utf-8"]) {
            encoding = NSUTF8StringEncoding;
        }
        else if ([encode.lowercaseString isEqualToString:@"gb2312"])
        {
            encoding = CFStringConvertEncodingToNSStringEncoding(kCFStringEncodingGB_18030_2000);
        }
        else if ([encode.lowercaseString isEqualToString:@"gbk"])
        {
            encoding = CFStringConvertEncodingToNSStringEncoding(kCFStringEncodingGB_18030_2000);
        }
        else if ([encode.lowercaseString isEqualToString:@"big5"])
        {
            encoding = CFStringConvertEncodingToNSStringEncoding(kCFStringEncodingBig5);
        }
        else
        {
            encoding = NSUTF8StringEncoding;
        }
        
        NSString *dataStr = [[NSString alloc] initWithData:_data encoding:encoding];
        [invokeResult SetResultText:dataStr];
        [self.EventCenter FireEvent:@"success" :invokeResult];
    }
    else
    {
        NSMutableDictionary *jsonNode = [NSMutableDictionary new];
        [jsonNode setObject:@(_statusCode) forKey:@"status" ];
        [jsonNode setObject:@"请求发生错误" forKey:@"message"];
        [invokeResult SetResultNode:jsonNode];
        [self.EventCenter FireEvent:@"fail" :invokeResult];
    }
    [self fireResultEvent];
    //清空头部设置，避免影响下次请求
    [self.setCookieDict removeAllObjects];
    _connection = nil;
}
- (void)fireResultEvent
{
    doInvokeResult *invokeResult = [doInvokeResult new];
    NSMutableDictionary *jsonNode = [NSMutableDictionary new];
    //拿到属性
    NSString *encode = [self GetPropertyValue:@"responseEncoding"];
    if ([encode isEqualToString:@""]) {
        encode = [self GetProperty:@"responseEncoding"].DefaultValue;
    }
    NSStringEncoding encoding;
    if ([encode.lowercaseString isEqualToString:@"utf-8"]) {
        encoding = NSUTF8StringEncoding;
    }
    else if ([encode.lowercaseString isEqualToString:@"gb2312"])
    {
        encoding = CFStringConvertEncodingToNSStringEncoding(kCFStringEncodingGB_18030_2000);
    }
    else if ([encode.lowercaseString isEqualToString:@"gbk"])
    {
        encoding = CFStringConvertEncodingToNSStringEncoding(kCFStringEncodingGB_18030_2000);
    }
    else if ([encode.lowercaseString isEqualToString:@"big5"])
    {
        encoding = CFStringConvertEncodingToNSStringEncoding(kCFStringEncodingBig5);
    }
    else
    {
        encoding = NSUTF8StringEncoding;
    }

    NSString *dataStr = [[NSString alloc] initWithData:_data encoding:encoding];
    if (!dataStr) {
        dataStr = @"";
    }
    [jsonNode setObject:@(_statusCode) forKey:@"status"];
    [jsonNode setObject:dataStr forKey:@"data"];
    [invokeResult SetResultNode:jsonNode];
    [self.EventCenter FireEvent:@"result" :invokeResult];
}

- (void)connection:(NSURLConnection *)connection didFailWithError:(NSError *)error
{
    NSMutableDictionary *jsonNode = [[NSMutableDictionary alloc] init];
    NSMutableDictionary *resultNode = [[NSMutableDictionary alloc]init];
    if (error.code == -1005 || error.code == -1009) {
        
        [jsonNode setObject:@"408" forKey:@"status"];
        [jsonNode setObject:@"网络离线" forKey:@"message"];
        
        [resultNode setObject:@"408" forKey:@"status"];
        [resultNode setObject:@"网络离线" forKey:@"data"];
        
    }
    else
    {
        [jsonNode setObject:@"400" forKey:@"status"];
        [jsonNode setObject:[error localizedDescription] forKey:@"message"];
        
        [resultNode setObject:@"400" forKey:@"status"];
        [resultNode setObject:@"其他网络错误" forKey:@"data"];
    }
    [_invokeResult SetResultNode:jsonNode];
    [self.EventCenter FireEvent:@"fail" :_invokeResult];
    [_invokeResult SetResultNode:resultNode];
    [self.EventCenter FireEvent:@"result" :_invokeResult];
}
@end
