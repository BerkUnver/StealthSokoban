dsound_lib :: #system_library "dsound";

DirectSoundCreate8 :: (device: *void, ppds8: **IDirectSound8, outer: *void) -> s32 #foreign dsound_lib;


WAVEFORMATEX :: struct {
    wFormatTag: WORD;
    nChannels: WORD;
    nSamplesPerSec: DWORD;
    nAvgBytesPerSec: DWORD;
    nBlockAlign: WORD;
    wBitsPerSample: WORD;
    cbSize: WORD;
}

WAVE_FORMAT_PCM :: 1;

DSSCL_NORMAL        :: 0x1;
DSSCL_PRIORITY      :: 0x2;




// @Copypaste from the modules/Sound_Player stuff.




/*

Here are the ugly macros from C for when we want them:

DECLARE_INTERFACE_(IDirectSound, IUnknown)
{
    // IUnknown methods
    STDMETHOD(QueryInterface)       (THIS_ __in REFIID, __deref_out LPVOID*) PURE;
    STDMETHOD_(ULONG,AddRef)        (THIS) PURE;
    STDMETHOD_(ULONG,Release)       (THIS) PURE;

    // IDirectSound methods
    STDMETHOD(CreateSoundBuffer)    (THIS_ __in LPCDSBUFFERDESC pcDSBufferDesc, __deref_out LPDIRECTSOUNDBUFFER *ppDSBuffer, __null LPUNKNOWN pUnkOuter) PURE;
    STDMETHOD(GetCaps)              (THIS_ __out LPDSCAPS pDSCaps) PURE;
    STDMETHOD(DuplicateSoundBuffer) (THIS_ __in LPDIRECTSOUNDBUFFER pDSBufferOriginal, __deref_out LPDIRECTSOUNDBUFFER *ppDSBufferDuplicate) PURE;
    STDMETHOD(SetCooperativeLevel)  (THIS_ HWND hwnd, DWORD dwLevel) PURE;
    STDMETHOD(Compact)              (THIS) PURE;
    STDMETHOD(GetSpeakerConfig)     (THIS_ __out LPDWORD pdwSpeakerConfig) PURE;
    STDMETHOD(SetSpeakerConfig)     (THIS_ DWORD dwSpeakerConfig) PURE;
    STDMETHOD(Initialize)           (THIS_ __in_opt LPCGUID pcGuidDevice) PURE;
};


DECLARE_INTERFACE_(IDirectSoundBuffer8, IDirectSoundBuffer)
{
    // IUnknown methods
    STDMETHOD(QueryInterface)       (THIS_ _In_ REFIID, _Outptr_ LPVOID*) PURE;
    STDMETHOD_(ULONG,AddRef)        (THIS) PURE;
    STDMETHOD_(ULONG,Release)       (THIS) PURE;

    // IDirectSoundBuffer methods
    STDMETHOD(GetCaps)              (THIS_ _Out_ LPDSBCAPS pDSBufferCaps) PURE;
    STDMETHOD(GetCurrentPosition)   (THIS_ _Out_opt_ LPDWORD pdwCurrentPlayCursor, _Out_opt_ LPDWORD pdwCurrentWriteCursor) PURE;
    STDMETHOD(GetFormat)            (THIS_ _Out_writes_bytes_opt_(dwSizeAllocated) LPWAVEFORMATEX pwfxFormat, DWORD dwSizeAllocated, _Out_opt_ LPDWORD pdwSizeWritten) PURE;
    STDMETHOD(GetVolume)            (THIS_ _Out_ LPLONG plVolume) PURE;
    STDMETHOD(GetPan)               (THIS_ _Out_ LPLONG plPan) PURE;
    STDMETHOD(GetFrequency)         (THIS_ _Out_ LPDWORD pdwFrequency) PURE;
    STDMETHOD(GetStatus)            (THIS_ _Out_ LPDWORD pdwStatus) PURE;
    STDMETHOD(Initialize)           (THIS_ _In_ LPDIRECTSOUND pDirectSound, _In_ LPCDSBUFFERDESC pcDSBufferDesc) PURE;
    STDMETHOD(Lock)                 (THIS_ DWORD dwOffset, DWORD dwBytes,
                                           _Outptr_result_bytebuffer_(*pdwAudioBytes1) LPVOID *ppvAudioPtr1, _Out_ LPDWORD pdwAudioBytes1,
                                           _Outptr_opt_result_bytebuffer_(*pdwAudioBytes2) LPVOID *ppvAudioPtr2, _Out_opt_ LPDWORD pdwAudioBytes2, DWORD dwFlags) PURE;
    STDMETHOD(Play)                 (THIS_ DWORD dwReserved1, DWORD dwPriority, DWORD dwFlags) PURE;
    STDMETHOD(SetCurrentPosition)   (THIS_ DWORD dwNewPosition) PURE;
    STDMETHOD(SetFormat)            (THIS_ _In_ LPCWAVEFORMATEX pcfxFormat) PURE;
    STDMETHOD(SetVolume)            (THIS_ LONG lVolume) PURE;
    STDMETHOD(SetPan)               (THIS_ LONG lPan) PURE;
    STDMETHOD(SetFrequency)         (THIS_ DWORD dwFrequency) PURE;
    STDMETHOD(Stop)                 (THIS) PURE;
    STDMETHOD(Unlock)               (THIS_ _In_reads_bytes_(dwAudioBytes1) LPVOID pvAudioPtr1, DWORD dwAudioBytes1,
                                           _In_reads_bytes_opt_(dwAudioBytes2) LPVOID pvAudioPtr2, DWORD dwAudioBytes2) PURE;
    STDMETHOD(Restore)              (THIS) PURE;

    // IDirectSoundBuffer8 methods
    STDMETHOD(SetFX)                (THIS_ DWORD dwEffectsCount, _In_reads_opt_(dwEffectsCount) LPDSEFFECTDESC pDSFXDesc, _Out_writes_opt_(dwEffectsCount) LPDWORD pdwResultCodes) PURE;
    STDMETHOD(AcquireResources)     (THIS_ DWORD dwFlags, DWORD dwEffectsCount, _Out_writes_(dwEffectsCount) LPDWORD pdwResultCodes) PURE;
    STDMETHOD(GetObjectInPath)      (THIS_ _In_ REFGUID rguidObject, DWORD dwIndex, _In_ REFGUID rguidInterface, _Outptr_ LPVOID *ppObject) PURE;
};

*/

#scope_export

OUTPUT_SAMPLING_RATE :: 44100;

PRIMARY_BUFFER_SIZE_IN_BYTES :: 0;
FILL_BUFFER_SIZE_IN_SAMPLES  :: 24000;  // @Cleanup: When we can do constexpr math, this should be: OUTPUT_SAMPLING_RATE / 2 or something like that.

DS_OK :: 0;

DSBPLAY_LOOPING      :: 0x01;

DSBSTATUS_PLAYING           :: 0x001;
DSBSTATUS_BUFFERLOST        :: 0x002;
DSBSTATUS_LOOPING           :: 0x004;
DSBSTATUS_LOCHARDWARE       :: 0x008;
DSBSTATUS_LOCSOFTWARE       :: 0x010;
DSBSTATUS_TERMINATED        :: 0x020;

//
// DirectSound Stuff:
//

WAVE_FORMAT_EXTENSIBLE         :: 0xFFFE;


// @Incomplete:: Eventually we can uncomment this, but
// right now the #run directive return value handling does not
// handle big return values and GUID is big! Because the return value
// is put back into the AST, we would need an AST Literal for
// a binary blob, I think. Weird and I don't want to do it yet.
// -jblow, 19 September 2015
//
// KSDATAFORMAT_SUBTYPE_PCM :: #run string_to_guid("00000001-0000-0010-8000-00aa00389b71");

// init_KSDATAFORMAT_SUBTYPE_PCM :: (dest: *GUID) { <<dest = string_to_guid("00000001-0000-0010-8000-00aa00389b71"); }


SPEAKER_FRONT_LEFT             :: 0x1;
SPEAKER_FRONT_RIGHT            :: 0x2;
SPEAKER_FRONT_CENTER           :: 0x4;
SPEAKER_LOW_FREQUENCY          :: 0x8;
SPEAKER_BACK_LEFT              :: 0x10;
SPEAKER_BACK_RIGHT             :: 0x20;
SPEAKER_FRONT_LEFT_OF_CENTER   :: 0x40;
SPEAKER_FRONT_RIGHT_OF_CENTER  :: 0x80;
SPEAKER_BACK_CENTER            :: 0x100;
SPEAKER_SIDE_LEFT              :: 0x200;
SPEAKER_SIDE_RIGHT             :: 0x400;
SPEAKER_TOP_CENTER             :: 0x800;
SPEAKER_TOP_FRONT_LEFT         :: 0x1000;
SPEAKER_TOP_FRONT_CENTER       :: 0x2000;
SPEAKER_TOP_FRONT_RIGHT        :: 0x4000;
SPEAKER_TOP_BACK_LEFT          :: 0x8000;
SPEAKER_TOP_BACK_CENTER        :: 0x10000;
SPEAKER_TOP_BACK_RIGHT         :: 0x20000;


KSAUDIO_SPEAKER_MONO           :: SPEAKER_FRONT_CENTER;
KSAUDIO_SPEAKER_STEREO         :: SPEAKER_FRONT_LEFT | SPEAKER_FRONT_RIGHT;
KSAUDIO_SPEAKER_QUAD           :: SPEAKER_FRONT_LEFT | SPEAKER_FRONT_RIGHT |
                                  SPEAKER_BACK_LEFT  | SPEAKER_BACK_RIGHT;
KSAUDIO_SPEAKER_SURROUND       :: SPEAKER_FRONT_LEFT | SPEAKER_FRONT_RIGHT |
                                  SPEAKER_FRONT_CENTER | SPEAKER_BACK_CENTER;
KSAUDIO_SPEAKER_5POINT1        :: SPEAKER_FRONT_LEFT | SPEAKER_FRONT_RIGHT |
                                  SPEAKER_FRONT_CENTER | SPEAKER_LOW_FREQUENCY |
                                  SPEAKER_BACK_LEFT  | SPEAKER_BACK_RIGHT;
KSAUDIO_SPEAKER_7POINT1        :: SPEAKER_FRONT_LEFT | SPEAKER_FRONT_RIGHT |
                                  SPEAKER_FRONT_CENTER | SPEAKER_LOW_FREQUENCY |
                                  SPEAKER_BACK_LEFT | SPEAKER_BACK_RIGHT |
                                  SPEAKER_FRONT_LEFT_OF_CENTER | SPEAKER_FRONT_RIGHT_OF_CENTER;
KSAUDIO_SPEAKER_5POINT1_SURROUND :: SPEAKER_FRONT_LEFT | SPEAKER_FRONT_RIGHT |
                                    SPEAKER_FRONT_CENTER | SPEAKER_LOW_FREQUENCY |
                                    SPEAKER_SIDE_LEFT  | SPEAKER_SIDE_RIGHT;
KSAUDIO_SPEAKER_7POINT1_SURROUND :: SPEAKER_FRONT_LEFT | SPEAKER_FRONT_RIGHT |
                                    SPEAKER_FRONT_CENTER | SPEAKER_LOW_FREQUENCY |
                                    SPEAKER_BACK_LEFT | SPEAKER_BACK_RIGHT |
                                    SPEAKER_SIDE_LEFT | SPEAKER_SIDE_RIGHT;

// The following are obsolete 5.1 and 7.1 settings (they lack side speakers).  Note this means
// that the default 5.1 and 7.1 settings (KSAUDIO_SPEAKER_5POINT1 and KSAUDIO_SPEAKER_7POINT1 are
// similarly obsolete but are unchanged for compatibility reasons).
//KSAUDIO_SPEAKER_5POINT1_BACK :: KSAUDIO_SPEAKER_5POINT1;
//KSAUDIO_SPEAKER_7POINT1_WIDE :: KSAUDIO_SPEAKER_7POINT1;


DSSPEAKER :: enum {
    HEADPHONE        :: 1;
    MONO             :: 2;
    QUAD             :: 3;
    STEREO           :: 4;
    SURROUND         :: 5;
    _5POINT1          :: 6;
    _5POINT1_BACK     :: _5POINT1;
    _5POINT1_SURROUND :: 9;
    _7POINT1          :: 7;
    _7POINT1_SURROUND :: 8;
    _7POINT1_WIDE     :: _7POINT1;
}

DSBCAPS_PRIMARYBUFFER      :: 0x1;
DSBCAPS_CTRLVOLUME         :: 0x80;
DSBCAPS_GLOBALFOCUS        :: 0x08000;
DSBCAPS_GETCURRENTPOSITION2:: 0x10000;

DSBUFFERCAPS :: struct {
}

IDirectSound8 :: struct {
    using vtable: *IDirectSound8Vtable;
}

IDirectSoundBuffer8 :: struct {
    using vtable: *IDirectSoundBuffer8Vtable;
}

IDirectSoundBuffer8Vtable :: struct {
    using base: IUnknown_VTable;

    GetCaps: (buffer: *IDirectSoundBuffer8, caps: *DSBUFFERCAPS) #c_call;
    GetCurrentPosition: (buffer: *IDirectSoundBuffer8, pdwCurrentPlayCursor: *s32, pdwCurrentWriteCursor: *s32) -> s32 #c_call;
    GetFormat: *void;
    GetVolume: *void;
    GetPan: *void;
    GetFrequency: *void;
    GetStatus:     (buffer: *IDirectSoundBuffer8, pdwStatus: *s32) -> s32 #c_call;
    Initialize:   *void;
    Lock: (buffer: *IDirectSoundBuffer8, dwOffset: s32, dwBytes: s32, pvAudioPtr1: **void, dwAudioBytes1: *s32, pvAudioPtr2: **void, dwAudioBytes2: *s32, dwFlags: s32) -> s32 #c_call;
    Play: (buffer: *IDirectSoundBuffer8, dwReserved1: s32, dwPriority: s32, dwFlags: s32) -> s32 #c_call;
    SetCurrentPosition: *void;
    SetFormat:  (buffer: *IDirectSoundBuffer8, format: *WAVEFORMATEX) -> s32 #c_call;
    SetVolume:    *void;
    SetPan:       *void;
    SetFrequency: *void;
    Stop: (buffer: *IDirectSoundBuffer8) -> s32 #c_call;
    Unlock: (buffer: *IDirectSoundBuffer8, pvAudioPtr1: *void, dwAudioBytes1: s32, pvAudioPtr2: *void, dwAudioBytes2: s32) -> s32 #c_call;

    Restore: (buffer: *IDirectSoundBuffer8) -> s32 #c_call;

    // IDirectSoundBuffer8 methods
    SetFX: *void;
    AcquireResources: *void;
    GetObjectInPath: *void;
}

IDirectSound8Vtable :: struct {
    using base: IUnknown_VTable;

    // IDirectSound methods
    CreateSoundBuffer: (dsound: *IDirectSound8, desc: *DSBUFFERDESC, buffer: **IDirectSoundBuffer8, outer: **void = null) -> s32 #c_call;

    GetCaps: *void;
    DuplicateSoundBuffer: *void;
    SetCooperativeLevel: (dsound: *IDirectSound8, hwnd: HWND, level: s32) -> s32 #c_call;
    Compact: *void;
    GetSpeakerConfig: (dsound: *IDirectSound8, config: *s32) -> s32 #c_call;
    SetSpeakerConfig: *void;
    Initialize: *void;
}

WAVEFORMATEXTENSIBLE :: struct {
    Format: WAVEFORMATEX;
    wValidBitsPerSample: s16;
    dwChannelMask: s32;
    SubFormat: GUID;
}

DSBUFFERDESC :: struct {
    dwSize        : s32;
    dwFlags       : s32;
    dwBufferBytes : s32;
    dwReserved    : s32;
    lpwfxFormat   : *WAVEFORMATEX;

    guid3DAlgorithm: GUID;
}



CONFIG :: (speaker_config: s32) -> DSSPEAKER {
    return cast(DSSPEAKER) (speaker_config & 0xff);
}

GEOMETRY :: (speaker_config: s32) -> u8 {
    return cast(u8) ((speaker_config >> 16) & 0xff);
}
