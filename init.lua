-- FFI binding to FFmpeg

local rel_dir = assert ( debug.getinfo ( 1 , "S" ).source:match ( [=[^@(.-[/\]?)[^/\]*$]=] ) , "Current directory unknown" ) .. "./"

local assert , error = assert , error
local setmetatable = setmetatable
local tonumber , tostring = tonumber , tostring
local tblinsert = table.insert

local ffi                 = require"ffi"
local ffi_util            = require"ffi_util"
local ffi_add_include_dir = ffi_util.ffi_add_include_dir
local ffi_defs            = ffi_util.ffi_defs

ffi_add_include_dir ( rel_dir .. "include" )

ffi_defs ( [[ffmpeg_funcs.h]] , [[ffmpeg_defs.h]] , {
		[[libavutil/avstring.h]] ;
		[[libavcodec/avcodec.h]] ;
		[[libavformat/avformat.h]] ;
	} )

local avutil , avcodec , avformat
assert ( jit , "jit table unavailable" )
if jit.os == "Windows" then -- Windows binaries from http://ffmpeg.zeranoe.com/builds/
	avutil 		= ffi.load ( rel_dir .. [[avutil-51]] )
	avcodec 	= ffi.load ( rel_dir .. [[avcodec-53]] )
	avformat 	= ffi.load ( rel_dir .. [[avformat-53]] )
elseif jit.os == "Linux" or jit.os == "OSX" or jit.os == "POSIX" or jit.os == "BSD" then
	avutil 		= ffi.load ( [[libavutil]] )
	avcodec 	= ffi.load ( [[libavcodec]] )
	avformat 	= ffi.load ( [[libavformat]] )
else
	error ( "Unknown platform" )
end

local ffmpeg = {
	avutil = avutil ;
	avcodec = avcodec ;
	avformat = avformat ;

	AV_TIME_BASE = 1000000 ;
}

ffmpeg.format_to_type = {
	--[avutil.AV_SAMPLE_FMT_NONE] 	= nil ;
	[avutil.AV_SAMPLE_FMT_U8] 	= "uint8_t" ;
	[avutil.AV_SAMPLE_FMT_S16] 	= "int16_t" ;
	[avutil.AV_SAMPLE_FMT_S32] 	= "int32_t" ;
	[avutil.AV_SAMPLE_FMT_FLT] 	= "float" ;
	[avutil.AV_SAMPLE_FMT_DBL] 	= "double" ;
	--[avutil.AV_SAMPLE_FMT_NB] 	= "" ;
}


local function avAssert ( err )
	if err < 0 then
		local errbuff = ffi.new ( "uint8_t[256]" )
		local ret = avutil.av_strerror ( err , errbuff , 256 )
		if ret ~= -1 then
			error ( ffi.string ( errbuff ) , 2 )
		else
			error ( "Unknown AV error: " .. tostring ( ret ) , 2 )
		end
	end
	return err
end
ffmpeg.avAssert = avAssert

function ffmpeg.openfile ( file )
	assert ( file , "No input file" )
	local formatContext_p = ffi.new ( "AVFormatContext*[1]" )
	avAssert ( avformat.avformat_open_input ( formatContext_p , file , nil , nil ) )
	local formatContext = ffi.gc ( formatContext_p[0] , avformat.av_close_input_stream )
	return formatContext
end

function ffmpeg.findaudiostreams ( formatContext )
	avAssert( avformat.av_find_stream_info ( formatContext ) )

	local audiostreams = { }
	local nStreams = tonumber ( formatContext.nb_streams )
	for i=0 , nStreams-1 do
		local ctx = formatContext.streams [ i ].codec
		if ctx.codec_type == avutil.AVMEDIA_TYPE_AUDIO then
			local codec = assert ( avcodec.avcodec_find_decoder ( ctx.codec_id ) , "Unsupported codec" )
			avAssert ( avcodec.avcodec_open ( ctx , codec ) )
			tblinsert ( audiostreams , ctx )
		end
	end

	return audiostreams
end

local packet = ffi.new ( "AVPacket" )
function ffmpeg.read_frames ( formatctx )
	return function ( formatctx , packet )
			if tonumber( avformat.url_feof ( formatctx.pb ) ) == 0 then
				avAssert ( avformat.av_read_frame ( formatctx , packet ) )
				return packet
			else
				return nil
			end
		end , formatctx , packet
end

avcodec.avcodec_init()
avcodec.avcodec_register_all()
avformat.av_register_all()

return ffmpeg
