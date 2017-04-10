
Namespace std.audio

#rem monkeydoc The AudioData class.
#end
Class AudioData

	#rem monkeydoc Invoked when audio data is discarded.
	#end
	Field OnDiscarded:Void()

	#rem monkeydoc Creates a new AudioData object
	#end
	Method New( length:Int,format:AudioFormat,hertz:Int )
	
		Local data:=libc.malloc( BytesPerSample( format )*length )
		
		_length=length
		_format=format
		_hertz=hertz
		_data=Cast<UByte Ptr>( data )
		
		OnDiscarded=Lambda()
			libc.free( data )
		End
	End

	Method New( length:Int,format:AudioFormat,hertz:Int,data:Void Ptr )
		_length=length
		_format=format
		_hertz=hertz
		_data=Cast<UByte Ptr>( data )
	End
	
	#rem monkeydoc The length, in samples, of the audio.
	#end
	Property Length:Int()
		Return _length
	End
	
	#rem monkeydoc The format of the audio.
	#end
	Property Format:AudioFormat()
		Return _format
	End
	
	#rem monkeydoc The playback rate of the audio.
	#end
	Property Hertz:Int()
		Return _hertz
	End

	#rem monkeydoc The duration, in seconds, of the audio.
	#end
	Property Duration:Double()
		Return Double(_length)/Double(_hertz)
	End

	#rem monkeydoc The actual audio data.
	#end	
	Property Data:UByte Ptr()
		Return _data
	End

	#rem monkeydoc The size, in bytes of the audio data.
	#end	
	Property Size:Int()
		Return BytesPerSample( _format ) * _length
	End
	
	#rem monkeydoc Gets a sample at a given sample index.
	
	@index must be in the range [0,Length).
	
	#end
	Method GetSample:Float( index:Int,channel:Int=0 )
		DebugAssert( index>=0 And index<_length )
		Select _format
		Case AudioFormat.Mono8
			Return _data[index]/128.0-1
		Case AudioFormat.Stereo8
			Return _data[index*2+(channel&1)]/128.0-1
		Case AudioFormat.Mono16
			Return Cast<Short Ptr>( _data )[index]/32767.0
		Case AudioFormat.Stereo16
			Return Cast<Short Ptr>( _data )[index*2+(channel&1)]/32767.0
		End
		Return 0
	End
	
	#rem monkeydoc @hidden Sets a sample at a given sample index.

	@index must be in the range [0,Length).
	
	#end
	Method SetSample( index:Int,channel:Int=0,sample:Float )
		DebugAssert( index>=0 And index<_length )
		
		RuntimeError( "TODO!" )
	End
	
	#rem monkeydoc Discards the audio data object.
	#end
	Method Discard()
		If _discarded Return
		_discarded=True
		OnDiscarded()
		_length=0
		_format=Null
		_data=Null
	End
	
	#rem monkey Loads audio data from a file.
	#end
	Function Load:AudioData( path:String )
	
		Select ExtractExt( path ).ToLower()
		Case ".wav" Return LoadAudioData_WAV( path )
		Case ".ogg" Return LoadAudioData_OGG( path )
		End
		
		Return Null
	End
	
	Private
	
	Field _length:Int
	Field _format:AudioFormat
	Field _hertz:Int
	Field _data:UByte Ptr
	Field _discarded:Bool
	
End
