// Offline tests for LRC parser/selection; no network.
#import "../Sources/PDLyricLogic.h"
#include <assert.h>
int main(void) { @autoreleasepool {
    NSArray *tl=PDLyric_parseLRC(@"[00:01.00]第一句\n[00:05.50]第二句\n[01:02.25]第三句");
    assert(tl.count==3);
    assert(!PDLyric_lineAt(tl,0.5));
    assert([PDLyric_lineAt(tl,1.0) isEqual:@"第一句"]);
    assert([PDLyric_lineAt(tl,3.0) isEqual:@"第一句"]);
    assert([PDLyric_lineAt(tl,5.5) isEqual:@"第二句"]);
    assert([PDLyric_lineAt(tl,62.3) isEqual:@"第三句"]);
    assert(!PDLyric_lineAt(tl,-1));
    NSArray *rows=@[
      @{@"duration":@220.0,@"instrumental":@NO,@"syncedLyrics":@"[00:02.00]A\n[00:08.00]B"},
      @{@"duration":@180.0,@"instrumental":@NO,@"syncedLyrics":@"[00:01.00]X\n[00:06.00]Y"},
      @{@"duration":@200.0,@"instrumental":@YES,@"syncedLyrics":@"[00:01.00]P"},
      @{@"duration":@500.0,@"instrumental":@NO,@"plainLyrics":@"no time"},
    ];
    NSArray *picked=PDLyric_pickTimeline(rows,222.0);
    assert(picked.count==2 && [picked[0][@"text"] isEqual:@"A"]);
    assert(!PDLyric_pickTimeline(@[],100));
    assert(!PDLyric_pickTimeline(rows,100));
    NSURL *u=PDLyric_searchURL(@"半壶纱",@"刘珂矣");
    assert([u.query containsString:@"track_name=%E5%8D%8A%E5%A3%B6%E7%BA%B1"]);
    puts("PASS PDLyric logic: LRC boundaries, nearest synced selection, URL encoding");
    return 0;
} }
