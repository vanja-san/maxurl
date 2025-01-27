#!/bin/bash

cd "`dirname "$0"`"

strip_whitespace() {
	sed -i -e 's/[ \t]*$//g' -e 's/^ *$//g' "$1"
}

# 3.1.2 has issues with our generated coub dash streams
wget http://cdn.dashjs.org/v3.1.1/dash.all.debug.js -O dash.all.debug.js
echo "" >> dash.all.debug.js
echo "var lib_export = dashjs;" >> dash.all.debug.js
cat shim.js >> dash.all.debug.js
dos2unix dash.all.debug.js
sed -i -e '/\/\/# sourceMappingURL=/d' dash.all.debug.js
strip_whitespace dash.all.debug.js

wget https://raw.githubusercontent.com/escolarea-labs/slowaes/f53404fb0aba47fcd336ae32623033bffa1dab41/js/aes.js -O aes.orig.js
cp aes.orig.js aes.patched.js
# patch is adapted from https://raw.githubusercontent.com/kyprizel/testcookie-nginx-module/eb9f7d65f50f054a0e7525cf6ad225ca076d1173/util/aes.patch
patch -p0 aes.patched.js < aes1.patch
cat aes.patched.js > testcookie_slowaes.js
echo "" >> testcookie_slowaes.js
echo "var lib_export = slowAES;" >> testcookie_slowaes.js
cat shim.js >> testcookie_slowaes.js
dos2unix testcookie_slowaes.js
strip_whitespace testcookie_slowaes.js
unix2dos testcookie_slowaes.js

wget https://github.com/video-dev/hls.js/releases/download/v0.14.13/hls.js -O hls.js
# 1/2: don't use window.XMLHttpRequest, in order to allow overriding it
# 3: avoids some warnings in devtools
sed -i \
	-e 's/xhr_loader_window\.XMLHttpRequest/XMLHttpRequest/g' \
	-e 's/window\.XMLHttpRequest/XMLHttpRequest/g' \
	-e '/\/\/# sourceMappingURL=hls.js.map/d' hls.js
echo "" >> hls.js
echo "var lib_export = this;" >> hls.js
strip_whitespace hls.js

wget https://cdnjs.cloudflare.com/ajax/libs/crypto-js/3.1.2/rollups/aes.js -O cryptojs_aes.js
echo "" >> cryptojs_aes.js
echo "var lib_export = CryptoJS;" >> cryptojs_aes.js
cat shim.js >> cryptojs_aes.js

wget https://unpkg.com/mux.js@5.7.0/dist/mux.js -O mux.orig.js
echo 'var muxjs=null;' > mux.lib.js
cat mux.orig.js >> mux.lib.js
# don't store in window
#sed -i 's/g\.muxjs *=/muxjs =/' mux.lib.js
sed -i 's/^(function(f){if(typeof exports/(function(f){muxjs = f();return;if(typeof exports/' mux.lib.js

wget https://ajax.googleapis.com/ajax/libs/shaka-player/3.0.6/shaka-player.compiled.debug.js -O shaka.debug.orig.js
# move exportTo outside the anonymous function scope
echo 'var _fakeGlobal={};var exportTo={};' > shaka_global.js
sed -i 's/var exportTo={};//g' shaka.debug.orig.js
cat mux.lib.js shaka_global.js shaka.debug.orig.js > shaka.debug.js
# XHR is same as above, to allow overriding
# the other window.* changes fixes it failing under the firefox addon
# disable fetch in order to force XHR
# remove sourcemapping to avoid warnings under devtools
sed -i \
    -e 's/window\.XMLHttpRequest/XMLHttpRequest/g' \
	-e 's/window\.decodeURIComponent/decodeURIComponent/g' \
	-e 's/window\.parseInt/parseInt/g' \
	-e 's/window\.muxjs/muxjs/g' \
	-e 's/innerGlobal\.shaka/_fakeGlobal.shaka/g' \
	-e 's/goog\.global\.XMLHttpRequest/XMLHttpRequest/g' \
	-e 's/\(HttpFetchPlugin.isSupported=function..{\)/\1return false;/g' \
	-e '/\/\/# sourceMappingURL=/d' shaka.debug.js
echo 'var lib_export = exportTo.shaka;' >> shaka.debug.js
cat shim.js >> shaka.debug.js

to_uricomponent() {
	cat "$@" | node -e 'var fs = require("fs"); var data = fs.readFileSync(0, "utf8"); process.stdout.write(encodeURIComponent(data));'
}

wget https://unpkg.com/@ffmpeg/ffmpeg@0.9.7/dist/ffmpeg.min.js -O ffmpeg.min.orig.js
wget https://unpkg.com/@ffmpeg/core@0.8.5/dist/ffmpeg-core.js -O ffmpeg-core.orig.js
cp ffmpeg-core.orig.js ffmpeg-core.js
# window.* and self->_fakeGlobal are for preventing leaking
# remove sourcemapping to avoid warnings under devtools
sed -i \
	-e 's/window.FFMPEG_CORE_WORKER_SCRIPT/FFMPEG_CORE_WORKER_SCRIPT/g' \
	-e 's/window\.createFFmpegCore/createFFmpegCore/g' \
	-e 's/(self,(function/(_fakeGlobal,(function/' \
	-e '/\/\/# sourceMappingURL=/d' ffmpeg.min.orig.js
# prevents blob urls from being used, fixes loading under chrome
# node is used instead of sed due to the size of ffmpeg-core.orig.js
node <<EOF
var fs = require("fs");
var ffmpeg = fs.readFileSync("ffmpeg.min.orig.js", "utf8");
var core = fs.readFileSync("ffmpeg-core.orig.js", "utf8");
//ffmpeg = ffmpeg.replace(/mainScriptUrlOrBlob:[a-zA-Z0-9]+,/, 'mainScriptUrlOrBlob:"data:application/x-javascript,' + encodeURIComponent(core) + '",');
ffmpeg = ffmpeg.replace(/mainScriptUrlOrBlob:[a-zA-Z0-9]+,/, 'mainScriptUrlOrBlob:new Blob([decodeURIComponent("' + encodeURIComponent(core) + '")]),');
fs.writeFileSync("ffmpeg.min.orig.js", ffmpeg);
EOF
# since ffmpeg-core is being prepended, this is necessary in order to have requests work properly
# note that the unpkg url is used instead of integrating it in the repo. this is for cache reasons, as all other scripts using ffmpeg.js will use the same url
sed -i 's/{return [a-z]*\.locateFile[?][a-z]*\.locateFile(a,[^}]*}var/{return "https:\/\/unpkg.com\/@ffmpeg\/core@0.8.5\/dist\/" + a}var/' ffmpeg-core.js
# inject the worker directly, fixes more cors issues
wget https://unpkg.com/@ffmpeg/core@0.8.5/dist/ffmpeg-core.worker.js -O ffmpeg-core.worker.js
WORKER_CODE=`to_uricomponent ffmpeg-core.worker.js`
#sed -i 's/{var a=..("ffmpeg-core.worker.js");\([^}]*\.push(new Worker(a))}\)/{var a="data:application\/x-javascript,'$WORKER_CODE'";\1/g' ffmpeg-core.js
# use blob instead of data, works on more sites (such as instagram)
sed -i 's/{var a=..("ffmpeg-core.worker.js");\([^}]*\.push(new Worker(a))}\)/{var a=URL.createObjectURL(new Blob([decodeURIComponent("'$WORKER_CODE'")]));\1/g' ffmpeg-core.js
# finally cat it all together
echo "var FFMPEG_CORE_WORKER_SCRIPT;var _fakeGlobal={window:window};" > ffmpeg.js
cat fetch_shim.js >> ffmpeg.js
cat ffmpeg-core.js >> ffmpeg.js
echo "" >> ffmpeg.js
cat ffmpeg.min.orig.js >> ffmpeg.js
echo "" >> ffmpeg.js
echo "var lib_export = _fakeGlobal.FFmpeg;" >> ffmpeg.js
cat shim.js >> ffmpeg.js
strip_whitespace ffmpeg.js

wget https://unpkg.com/mpd-parser@0.15.0/dist/mpd-parser.js -O mpd-parser.js
# isNaN prevents failing under firefox addon
# location.href is to avoid resolving to the local href (breaks v.redd.it dash streams)
sed -i \
	-e 's/}(this, (function (exports/}(_fakeGlobal, (function (exports/' \
	-e 's/window\.isNaN/isNaN/g' \
	-e 's/window__[^ ]*\.location\.href/""/g' mpd-parser.js
wget https://unpkg.com/m3u8-parser@4.5.0/dist/m3u8-parser.js -O m3u8-parser.js
sed -i 's/}(this, function (exports/}(_fakeGlobal, function (exports/' m3u8-parser.js
echo "var _fakeGlobal={window: window};" > stream_parser.js
cat mpd-parser.js m3u8-parser.js >> stream_parser.js
echo "" >> stream_parser.js
echo "var lib_export = { dash: _fakeGlobal.mpdParser, hls: _fakeGlobal.m3u8Parser };" >> stream_parser.js
cat shim.js >> stream_parser.js

wget https://raw.githubusercontent.com/Stuk/jszip/7c75dff02e729bd9985f15b560aa02944e14f238/dist/jszip.js -O jszip.orig.js
sed -i \
	-e 's/("undefined"!=typeof window.window:"undefined"!=typeof global.global:"undefined"!=typeof self.self:this)/(_fakeWindow)/g' \
	-e 's/("undefined"!=typeof window.window:void 0!==...:"undefined"!=typeof self?self:this)/(_fakeWindow)/g' \
	-e 's/if(typeof window!=="undefined"){g=window}/if(typeof _fakeWindow!=="undefined"){g=_fakeWindow}/g' \
	-e 's/typeof global !== "undefined" . global/typeof _fakeWindow !== "undefined" ? _fakeWindow/g' \
	jszip.orig.js
echo "var _fakeWindow={};" > jszip.js
cat jszip.orig.js >> jszip.js
echo "" >> jszip.js
echo "var lib_export = _fakeWindow.JSZip;" >> jszip.js
cat shim.js >> jszip.js

CLEANUP=1
if [ $CLEANUP -eq 1 ]; then
	rm \
		aes.orig.js aes.patched.js \
		shaka.debug.orig.js shaka_global.js \
		mux.orig.js mux.lib.js \
		ffmpeg.min.orig.js ffmpeg-core.orig.js ffmpeg-core.js ffmpeg-core.worker.js \
		mpd-parser.js m3u8-parser.js \
		jszip.orig.js
fi
