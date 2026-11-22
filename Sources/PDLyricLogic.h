#pragma once
#import <Foundation/Foundation.h>
#include <math.h>
#include <stdlib.h>
static NSArray<NSDictionary *> *PDLyric_parseLRC(NSString *text) {
    if(![text isKindOfClass:NSString.class] || text.length>524288) return @[];
    NSMutableArray<NSDictionary *> *entries=[NSMutableArray array];
    NSCharacterSet *space=[NSCharacterSet whitespaceAndNewlineCharacterSet];
    NSCharacterSet *digits=[NSCharacterSet decimalDigitCharacterSet];
    NSInteger offset=0; NSUInteger order=0;
    for(NSString *raw in [text componentsSeparatedByCharactersInSet:[NSCharacterSet newlineCharacterSet]]) {
        if(entries.count>=5000) break;
        NSString *line=[raw stringByTrimmingCharactersInSet:space];
        if([line hasPrefix:@"[offset:"] && [line hasSuffix:@"]"]) {
            NSString *value=[line substringWithRange:NSMakeRange(8,line.length-9)];
            NSScanner *scanner=[NSScanner scannerWithString:value]; long long parsed=0;
            if([scanner scanLongLong:&parsed] && scanner.isAtEnd && llabs(parsed)<=600000) offset=(NSInteger)parsed;
            continue;
        }
        NSMutableArray<NSNumber *> *times=[NSMutableArray array];
        NSUInteger cursor=0;
        while(cursor<line.length && [line characterAtIndex:cursor]=='[') {
            NSRange close=[line rangeOfString:@"]" options:0 range:NSMakeRange(cursor,line.length-cursor)];
            if(close.location==NSNotFound || close.location-cursor>14) break;
            NSString *tag=[line substringWithRange:NSMakeRange(cursor+1,close.location-cursor-1)];
            NSArray<NSString *> *parts=[tag componentsSeparatedByString:@":"];
            BOOL valid=parts.count==2 && parts[0].length>=1 && parts[0].length<=3;
            for(NSString *part in parts) if(part.length==0 || [[part stringByTrimmingCharactersInSet:digits] length]) valid=NO;
            if(valid) {
                double t=parts[0].doubleValue*60+parts[1].doubleValue;
                if(parts[1].length<=2 && parts[1].integerValue<60 && t>=0 && t<=21600) [times addObject:@(t)];
            } else if(parts.count==2) {
                NSArray<NSString *> *seconds=[parts[1] componentsSeparatedByString:@"."];
                if(seconds.count==2 && seconds[0].length==2 && seconds[1].length>=1 && seconds[1].length<=3 && parts[0].length>=1 && parts[0].length<=3) {
                    BOOL allDigits=YES;
                    for(NSString *part in @[parts[0],seconds[0],seconds[1]]) if([[part stringByTrimmingCharactersInSet:digits] length]) allDigits=NO;
                    if(allDigits && seconds[0].integerValue<60) {
                        double scale=seconds[1].length==1?10:seconds[1].length==2?100:1000;
                        double t=parts[0].doubleValue*60+seconds[0].doubleValue+seconds[1].doubleValue/scale;
                        if(t<=21600) [times addObject:@(t)];
                    }
                }
            }
            cursor=close.location+1;
        }
        if(times.count==0) continue;
        NSString *lyric=[[line substringFromIndex:cursor] stringByTrimmingCharactersInSet:space];
        if(lyric.length==0 || lyric.length>240) continue;
        for(NSNumber *stamp in times) {
            if(entries.count>=5000) break;
            double t=MAX(0,stamp.doubleValue+offset/1000.0);
            [entries addObject:@{@"time":@(t),@"text":lyric,@"order":@(order++)}];
        }
    }
    [entries sortUsingComparator:^NSComparisonResult(NSDictionary *a,NSDictionary *b) {
        NSComparisonResult cmp=[a[@"time"] compare:b[@"time"]];
        return cmp==NSOrderedSame?[a[@"order"] compare:b[@"order"]]:cmp;
    }];
    return entries;
}
static NSString *PDLyric_lineAt(NSArray<NSDictionary *> *timeline,double elapsed) {
    if(!isfinite(elapsed) || elapsed<0 || !timeline.count) return nil;
    NSUInteger lo=0,hi=timeline.count;
    while(lo<hi) { NSUInteger mid=lo+(hi-lo)/2; if([timeline[mid][@"time"] doubleValue]<=elapsed) lo=mid+1; else hi=mid; }
    return lo?timeline[lo-1][@"text"]:nil;
}
static __attribute__((unused)) NSArray *PDLyric_pickTimeline(id json,double duration) {
    if(![json isKindOfClass:NSArray.class]) return nil;
    double bestPenalty=DBL_MAX; NSArray *best=nil;
    for(id row in json) {
        if(![row isKindOfClass:NSDictionary.class]) continue;
        if([row[@"instrumental"] boolValue]) continue;
        id synced=row[@"syncedLyrics"];
        if(![synced isKindOfClass:NSString.class] || ![(NSString *)synced length]) continue;
        id dur=row[@"duration"];
        if(![dur isKindOfClass:NSNumber.class] || !isfinite([dur doubleValue])) continue;
        double penalty=fabs([dur doubleValue]-duration);
        if(penalty<bestPenalty) { NSArray *tl=PDLyric_parseLRC(synced); if(tl.count){bestPenalty=penalty;best=tl;} }
    }
    return best;
}
static __attribute__((unused)) NSURL *PDLyric_searchURL(NSString *title,NSString *artist) {
    if(![title isKindOfClass:NSString.class] || ![(NSString *)title length] || [(NSString *)title length]>200) return nil;
    NSURLComponents *components=[NSURLComponents componentsWithString:@"https://lrclib.net/api/search"];
    NSMutableArray *items=[NSMutableArray array];
    [items addObject:[NSURLQueryItem queryItemWithName:@"track_name" value:title]];
    if([artist isKindOfClass:NSString.class] && artist.length) [items addObject:[NSURLQueryItem queryItemWithName:@"artist_name" value:artist]];
    components.queryItems=items; return components.URL;
}
