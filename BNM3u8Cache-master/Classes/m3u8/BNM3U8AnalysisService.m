//
//  BNM3U8AnalysisService.m
//  m3u8Demo
//
//  Created by liangzeng on 6/14/19.
//  Copyright © 2019 liangzeng. All rights reserved.
//

#import "BNM3U8AnalysisService.h"
#import "NSString+m3u8.h"
#import "BNM3U8PlistInfo.h"
#import "BNM3U8PlistInfo.h"
#import "BNFileManager.h"
#import "NSURL+m3u8.h"
#import "M3U8PlaylistModel.h"
/*解析m3u8 和组装m3u8*/

NSString *fullPerfixPath(NSString *rootPath,NSString *url){
    return  [rootPath stringByAppendingPathComponent:[url md5]];
}

@implementation BNM3U8AnalysisService
+ (void)analysisWithURL:(NSString *)urlStr rootPath:(NSString *)rootPath resultBlock:(BNM3U8AnalysisServiceResultBlock)resultBlock
{
    NSLog(@"analysis start");
    NSString *oriM3u8Path = [fullPerfixPath(rootPath,urlStr) stringByAppendingPathComponent:@"ori.m3u8"];

    
    [[NSURL URLWithString:urlStr] m3u_loadAsyncCompletion:^(M3U8PlaylistModel *model, NSError *error) {
        NSLog(@"model: %@  masterPlaylist:%@ \n mainMediaPl:%@",model,model.masterPlaylist.xStreamList,model.mainMediaPl.segmentList);
        if (!error && model) {
            [BNM3U8AnalysisService analysisWithOriUrlStringNew:urlStr rootPath:rootPath model:model resultBlock:resultBlock];
        }
        else{
            if (resultBlock) {
                resultBlock([[NSError alloc]initWithDomain:@"原始m3u8文本文件解析错误" code:NSURLErrorUnknown userInfo:nil],nil);
            }
        }

    }];
    return;
    
    //    NSString *oriM3u8String = [NSString stringWithContentsOfFile:oriM3u8Path encoding:0 error:nil];
    NSURLSessionDataTask *task = [[NSURLSession sharedSession]dataTaskWithURL:[NSURL URLWithString:urlStr] completionHandler:^(NSData * _Nullable data, NSURLResponse * _Nullable response, NSError * _Nullable error) {
        NSString * oriM3u8String  =[[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
        __block BOOL happenException = NO;
        if (oriM3u8String.length) {
            NSLog(@"use local oriM3u8Info");
            @try {
                [BNM3U8AnalysisService analysisWithOriUrlString:urlStr m3u8String:oriM3u8String rootPath:rootPath resultBlock:resultBlock];
            } @catch (NSException *exception) {
                happenException = YES;
                [[BNFileManager shareInstance]removeFileWithPath:oriM3u8Path];
                resultBlock([[NSError alloc]initWithDomain:@"原始m3u8文本文件解析错误" code:NSURLErrorUnknown userInfo:@{@"info":exception.reason}],nil);
            } @finally {
                
            }
            if (!happenException) {
                return;
            }
        }
        
        happenException = NO;
        NSString *m3u8Str = nil;
        @try {
            NSError *error = nil;
            
            m3u8Str = [[NSString alloc] initWithContentsOfURL:[NSURL URLWithString:urlStr] usedEncoding:0 error:&error];
            
            if (error)
            {
                resultBlock(error,nil);
                return ;
            }
            if (m3u8Str.length == 0)
            {
                resultBlock([[NSError alloc]initWithDomain:@"原始m3u8文件内容为空" code:NSURLErrorBadServerResponse userInfo:nil],nil);
                return;
            }
            [BNM3U8AnalysisService analysisWithOriUrlString:urlStr m3u8String:m3u8Str rootPath:rootPath resultBlock:resultBlock];
        } @catch (NSException *exception) {
            happenException = YES;
            resultBlock([[NSError alloc]initWithDomain:@"原始m3u8文本文件解析错误" code:NSURLErrorUnknown userInfo:@{@"info":exception.reason}],nil);
        } @finally {}
        
        if (!happenException) {
            /// save dst m3u8 info file
            NSString *dstM3u8Path = [fullPerfixPath(rootPath,urlStr) stringByAppendingPathComponent:@"local.m3u8"];
            [[BNFileManager shareInstance]saveDate:[m3u8Str dataUsingEncoding:NSUTF8StringEncoding] ToFile:dstM3u8Path completaionHandler:nil];
        }
    }];
    [task resume];
}
//----------------------------引入新的三方库解析M3U8文件--------------------------------
+ (void)analysisWithOriUrlStringNew:(NSString*)OriUrlString rootPath:(NSString *)rootPath model:(M3U8PlaylistModel *)model resultBlock:(BNM3U8AnalysisServiceResultBlock)resultBlock{
//    /*
//     "https://bitmovin-a.akamaihd.net/content/playhouse-vr/m3u8s/105560_video_360_1000000.m3u8"
//     https://bitmovin-a.akamaihd.net/content/playhouse-vr/
//     */
//    /*如果是相对路径 需要特殊处理*/
    if (!model && resultBlock) {
        resultBlock([[NSError alloc]initWithDomain:@"原始m3u8文本文件解析错误" code:NSURLErrorUnknown userInfo:nil],nil);
        return;
    }
    BOOL isParserFailed = NO;
    NSURL* baseUrl;
    NSString* m3u8String = model.mainMediaPl.originalText;
    BNM3U8PlistInfo *info = [BNM3U8PlistInfo new];
    /*
     &&M3U8 解析1 区分类别
     */
    if (model.masterPlaylist) {
        /* 1_1 Master playlist
           Extension - 可以在此处判断支持的视频清晰度
         */
        baseUrl = model.masterPlaylist.baseURL;
        M3U8ExtXStreamInf* exStreamInfo = [model.masterPlaylist.xStreamList firstStreamInf];
        if (exStreamInfo) {
            //M3U8的嵌套- 需要替换为嵌套的baseUrl
            if (exStreamInfo.m3u8URL) {
                baseUrl = exStreamInfo.m3u8URL;
            }
            info.version = model.masterPlaylist.version;
#warning 注意分两种类型（一嵌套的url加密 以及 二segment里的信息加密） - 此处暂时忽略第一种
            if (model.mainMediaPl.segmentList.count) {
                M3U8SegmentInfo* segment = [model.mainMediaPl.segmentList segmentInfoAtIndex:0];
                info.keyMethod = segment.xKey.method;
                info.keyUri = segment.xKey.url;
                info.keyIv = segment.xKey.iV;
            }
            if (!info.version) {
                info.version = [[m3u8String subStringFrom:@"#EXT-X-VERSION:" to:@"#"] removeSpaceAndNewline];
            }
            info.targetduration = [[m3u8String subStringFrom:@"#EXT-X-TARGETDURATION:" to:@"#"] removeSpaceAndNewline];
            info.mediaSequence = [[m3u8String subStringFrom:@"#EXT-X-MEDIA-SEQUENCE:" to:@"#"] removeSpaceAndNewline];
        }
        else{
            isParserFailed = YES;
        }
    }
    else{
        if (!model.mainMediaPl) {
            isParserFailed = YES;
        }
        //1_2 Media playlist
        baseUrl = model.mainMediaPl.baseURL;
        
        /*
         注意 无论是master playlist还是mediaplaylist 目前在本地都会存储为 mediaplaylist的形式
         */
        info.targetduration = [[m3u8String subStringFrom:@"#EXT-X-TARGETDURATION:" to:@"#"] removeSpaceAndNewline];
        info.mediaSequence = [[m3u8String subStringFrom:@"#EXT-X-MEDIA-SEQUENCE:" to:@"#"] removeSpaceAndNewline];
        info.keyMethod = [m3u8String subStringFrom:@"#EXT-X-KEY:METHOD=" to:@","];
        info.keyUri = [m3u8String subStringFrom:@"URI=\"" to:@"\""];
        info.keyIv = [[m3u8String subStringFrom:@"IV=" to:@"#"] removeSpaceAndNewline];
        if (!info.version) {
            info.version = [[m3u8String subStringFrom:@"#EXT-X-VERSION:" to:@"#"] removeSpaceAndNewline];
        }

    }
//    NSString* baseUrlLastPath = [baseUrl stringByDeletingLastPathComponent];//上一级目录
//    NSString* baseUrlRootPath;//根目录
//    NSRange   location;
////    for (int i = 0; i < 2; i ++) {
////        location = [baseUrlLastPath rangeOfString:@"/" options:NSBackwardsSearch];
////        baseUrlLastPath = location.location == NSNotFound ? nil : ([baseUrlLastPath substringToIndex:location.location]);
////    }
//    baseUrlLastPath = baseUrlLastPath ? [baseUrlLastPath stringByAppendingString:@"/"] : nil;
//
//    location = [baseUrl rangeOfString:@"/"];
//    baseUrlRootPath = location.location == NSNotFound ? nil : ([baseUrl substringToIndex:location.location]);
//    baseUrlRootPath = baseUrlRootPath ? [baseUrlRootPath stringByAppendingString:@"/"] : nil;
 
    if (info.keyMethod) {
        /*&&M3U8 解析 -- 此处替换为真是网络地址 */
//        NSString* netTsUri = info.keyUri;
//        /*相对地址替换
//         */
//        if ([netTsUri containsString:@"../"]) {
//            //上一级目录
//            netTsUri = [netTsUri stringByReplacingOccurrencesOfString:@"../" withString:baseUrlLastPath];
//        }
//        if ([netTsUri containsString:@"./"]) {
//            //当前目录
//            netTsUri = [netTsUri stringByReplacingOccurrencesOfString:@"./" withString:@""];
//        }
//        if ([netTsUri hasPrefix:@"/"]) {
//            //根目录
//            netTsUri = [netTsUri stringByReplacingOccurrencesOfString:@"/" withString:baseUrlRootPath];
//        }
//        NSRange markerRange = [netTsUri rangeOfString:@"://"];
//        if (markerRange.location == NSNotFound) {
//            //添加真实地址
//            netTsUri = [baseUrl stringByAppendingPathComponent:netTsUri];
//        }
        info.keyUri = [NSURL URLWithString:info.keyUri relativeToURL:baseUrl].absoluteString;
    }
    
//    /*
//     &&M3U8 判断是master playlist 还是 media playlist
//     */
//
//    info.version = model.mainMediaPl.version;
//    //media playlist attribute
//    BOOL isParserFailed = NO;
//    if (model.mainMediaPl) {
//        m3u8String = model.mainMediaPl.originalText;
//        baseUrl = model.mainMediaPl.baseURL.absoluteString;
//
//        if (model.masterPlaylist) {
//            /*
//             此处是master playlist的适配情况
//             extension - 可以在此处判断支持的视频清晰度
//             */
//            M3U8ExtXStreamInf* exStreamInfo = [model.masterPlaylist.xStreamList firstStreamInf];
//            if (model.masterPlaylist.xStreamList && exStreamInfo) {
//                //M3U8的嵌套
//                NSString* masterM3u8Url = exStreamInfo.m3u8URL.absoluteString;
//                baseUrl = [masterM3u8Url stringByDeletingLastPathComponent];
//                info.version = model.masterPlaylist.version;
//            }
//            else{
//                isParserFailed = YES;
//            }
//        }
//
//    }
//    else{
//        isParserFailed = YES;
//    }
    if (isParserFailed) {
        if (resultBlock) {
            resultBlock([[NSError alloc]initWithDomain:@"原始m3u8文本文件解析错误" code:NSURLErrorUnknown userInfo:nil],nil);
        }
        return;
    }
 
#warning 区分master list 情况
    NSMutableArray *fileInfos = @[].mutableCopy;
    if (info.keyUri.length > 0) {
        ///加入到 fileInfos
        BNM3U8fileInfo *fileInfo = [BNM3U8fileInfo new];
        fileInfo.oriUrlString = info.keyUri;
        fileInfo.index = - 1;
        /* /md5(url)/keyName*/
        fileInfo.relativeUrl =  [NSString stringWithFormat:@"%@/key",[OriUrlString md5]];
        [fileInfos addObject:fileInfo];
        fileInfo.diskPath =  [NSString stringWithFormat:@"%@/%@",rootPath,fileInfo.relativeUrl];

    }
//    NSRange tsRange = [m3u8String rangeOfString:@"#EXTINF:"];
//    if (tsRange.location == NSNotFound) {
//        resultBlock([[NSError alloc]initWithDomain:@"没有找到.ts文件信息" code:NSURLErrorUnknown userInfo:@{@"info":@"none downloadUrl for .ts file"}],nil);
//        return;
//    }
 
    @synchronized (self) {
        NSInteger segmentCount = model.mainMediaPl.segmentList.count;
        for (int i = 0; i < segmentCount; i++) {
            M3U8SegmentInfo* segment = [model.mainMediaPl.segmentList segmentInfoAtIndex:i];
            
            BNM3U8fileInfo*  fileInfo = [BNM3U8fileInfo new];
            fileInfo.duration = [NSString stringWithFormat:@"%lf",segment.duration];

            /*&&M3U8 解析 -- 此处替换为真是网络地址 */
//            NSString* netTsUri = segment.URI.absoluteString;
//            if ([netTsUri containsString:@"../"]) {
//                //相对地址替换
//                netTsUri = [netTsUri stringByReplacingOccurrencesOfString:@"../" withString:baseUrlLastPath];
//            }
//            if ([netTsUri containsString:@"./"]) {
//                netTsUri = [netTsUri stringByReplacingOccurrencesOfString:@"./" withString:@""];
//            }
//            NSRange markerRange = [netTsUri rangeOfString:@"://"];
//            if (markerRange.location == NSNotFound) {
//                //添加真实地址
//                netTsUri = [baseUrl stringByAppendingPathComponent:netTsUri];
//            }
            fileInfo.oriUrlString = [NSURL URLWithString:segment.URI.absoluteString relativeToURL:baseUrl].absoluteString;
 
            NSRange discontinuityRange = [m3u8String rangeOfString:@"#EXT-X-DISCONTINUITY"];
            if (discontinuityRange.location != NSNotFound) {
                fileInfo.hasDiscontiunity = YES;
            }
            fileInfo.index = i;
            /* /md5(url)/fileName*/
            fileInfo.relativeUrl = [NSString stringWithFormat:@"%@/%@.ts",[OriUrlString md5],@(fileInfo.index)];
            fileInfo.diskPath =  [NSString stringWithFormat:@"%@/%@",rootPath,fileInfo.relativeUrl];
            [fileInfos addObject:fileInfo];
        }
    }
    NSLog(@"analysis compelte");
    info.fileInfos = fileInfos;
    NSParameterAssert(resultBlock);
    if (resultBlock) {
        
        resultBlock(nil,info);
    }
}
 
//------------------------------------------------------------
+ (void)analysisWithOriUrlString:(NSString*)OriUrlString m3u8String:(NSString*)m3u8String rootPath:(NSString *)rootPath resultBlock:(BNM3U8AnalysisServiceResultBlock)resultBlock
{
    /*
     "https://bitmovin-a.akamaihd.net/content/playhouse-vr/m3u8s/105560_video_360_1000000.m3u8"
     https://bitmovin-a.akamaihd.net/content/playhouse-vr/
     */
    /*如果是相对路径 需要特殊处理*/
    if([m3u8String containsString:@"../"])
    {
        NSRange r;
        NSString *a = OriUrlString;
        for (int i = 0; i < 2; i ++) {
            r = [a rangeOfString:@"/" options:NSBackwardsSearch];
            a = [a substringToIndex:r.location];
        }
        a = [a stringByAppendingString:@"/"];
        m3u8String = [m3u8String stringByReplacingOccurrencesOfString:@"../" withString:a];
    }
    BNM3U8PlistInfo *info = [BNM3U8PlistInfo new];
    info.version = [[m3u8String subStringFrom:@"#EXT-X-VERSION:" to:@"#"] removeSpaceAndNewline];
    info.targetduration = [[m3u8String subStringFrom:@"#EXT-X-TARGETDURATION:" to:@"#"] removeSpaceAndNewline];
    info.mediaSequence = [[m3u8String subStringFrom:@"#EXT-X-MEDIA-SEQUENCE:" to:@"#"] removeSpaceAndNewline];
    
    info.keyMethod = [m3u8String subStringFrom:@"#EXT-X-KEY:METHOD=" to:@","];
    info.keyUri = [m3u8String subStringFrom:@"URI=\"" to:@"\""];
    info.keyIv = [[m3u8String subStringFrom:@"IV=" to:@"#"] removeSpaceAndNewline];
    
    NSMutableArray *fileInfos = @[].mutableCopy;
    if (info.keyUri.length > 0) {
        ///加入到 fileInfos
        BNM3U8fileInfo *fileInfo = [BNM3U8fileInfo new];
        fileInfo.oriUrlString = info.keyUri;
        fileInfo.index = - 1;
        /* /md5(url)/keyName*/
        fileInfo.relativeUrl =  [NSString stringWithFormat:@"%@/key",[OriUrlString md5]];
        [fileInfos addObject:fileInfo];
        fileInfo.diskPath =  [NSString stringWithFormat:@"%@/%@",rootPath,fileInfo.relativeUrl];
        
    }
    NSRange tsRange = [m3u8String rangeOfString:@"#EXTINF:"];
    if (tsRange.location == NSNotFound) {
        resultBlock([[NSError alloc]initWithDomain:@"没有找到.ts文件信息" code:NSURLErrorUnknown userInfo:@{@"info":@"none downloadUrl for .ts file"}],nil);
        return;
    }
    NSInteger index = 0;
    m3u8String = [m3u8String substringFromIndex:tsRange.location];
    while (tsRange.location != NSNotFound) {
        @autoreleasepool {
            BNM3U8fileInfo *fileInfo = [BNM3U8fileInfo new];
            fileInfo.duration = [m3u8String subStringFrom:@"#EXTINF:" to:@","];
            m3u8String = [m3u8String subStringForm:@"," offset:1];
            fileInfo.oriUrlString = [[m3u8String subStringTo:@"#"] removeSpaceAndNewline];
            NSRange exRange = [m3u8String rangeOfString:@"#EX"];
            NSRange discontinuityRange = [m3u8String rangeOfString:@"#EXT-X-DISCONTINUITY"];
            if (exRange.location == discontinuityRange.location) {
                fileInfo.hasDiscontiunity = YES;
            }
            fileInfo.index = index ++;
            /* /md5(url)/fileName*/
            fileInfo.relativeUrl = [NSString stringWithFormat:@"%@/%@.ts",[OriUrlString md5],@(fileInfo.index)];
            fileInfo.diskPath =  [NSString stringWithFormat:@"%@/%@",rootPath,fileInfo.relativeUrl];
            [fileInfos addObject:fileInfo];
            tsRange = [m3u8String rangeOfString:@"#EXTINF:"];
            if (tsRange.location != NSNotFound) {
                m3u8String = [m3u8String subStringForm:@"#EXTINF:" offset:0];
            }
        }
    }
    NSLog(@"analysis compelte");
    info.fileInfos = fileInfos;
    NSParameterAssert(resultBlock);
    resultBlock(nil,info);
}

+ (NSString*)synthesisLocalM3u8Withm3u8Info:(BNM3U8PlistInfo *)m3u8Info withLocaHost:(nonnull NSString *)localhost
{
    if (!localhost.length) {
        localhost = @"http://127.0.0.1:8080";
    }
    NSString *newM3u8String = @"";
    
    NSString *header = @"#EXTM3U\n";
    if (m3u8Info.version.length) {
        header = [header stringByAppendingString:[NSString stringWithFormat:@"#EXT-X-VERSION:%ld\n",(long)m3u8Info.version.integerValue]];
    }
    if (m3u8Info.targetduration.length) {
        header = [header stringByAppendingString:[NSString stringWithFormat:@"#EXT-X-TARGETDURATION:%ld\n",(long)m3u8Info.targetduration.integerValue]];
    }
    if (m3u8Info.mediaSequence.length) {
        header = [header stringByAppendingString:[NSString stringWithFormat:@"#EXT-X-MEDIA-SEQUENCE:%ld\n",(long)m3u8Info.mediaSequence.integerValue]];
    }
    
    __block NSString *keyStr = @"";
    __block NSString *body = @"";
    
    [m3u8Info.fileInfos enumerateObjectsUsingBlock:^(BNM3U8fileInfo * _Nonnull obj, NSUInteger idx, BOOL * _Nonnull stop) {
        if(obj.index == -1 ){
            if(m3u8Info.keyIv.length) {
                    keyStr = [NSString stringWithFormat:@"#EXT-X-KEY:METHOD=%@,URI=\"%@\",IV=%@\n",m3u8Info.keyMethod,[localhost stringByAppendingString:obj.relativeUrl],m3u8Info.keyIv];
            } else {
                keyStr = [NSString stringWithFormat:@"#EXT-X-KEY:METHOD=%@,URI=\"%@\"\n",m3u8Info.keyMethod,[localhost stringByAppendingString:obj.relativeUrl]];
            }
        }
        else{
            NSString *tsInfo = [NSString stringWithFormat:@"#EXTINF:%.6lf,\n%@\n",obj.duration.floatValue,[localhost stringByAppendingString:obj.relativeUrl]];
            body =  [body stringByAppendingString:tsInfo];
            if (obj.isHasDiscontiunity) body = [body stringByAppendingString:@"#EXT-X-DISCONTINUITY\n"];
        }
    }];
    
    newM3u8String = [[[[newM3u8String stringByAppendingString:header] stringByAppendingString:keyStr] stringByAppendingString:body] stringByAppendingString:@"#EXT-X-ENDLIST"];
    
    return newM3u8String;
}

@end
