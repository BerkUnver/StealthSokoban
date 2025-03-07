xaudio2 :: #system_library "XAudio2_8";
// @Incomplete I think we should just bundle the xaudio in this executable if possible?
// I think #system_library links to an import library?

XAudio2Create :: (ppXAudio2: **IXAudio2, flags: u32, XAudio2Processor: XAUDIO2_PROCESSOR) -> HRESULT #foreign xaudio2;


XAUDIO2_PROCESSOR :: enum_flags {
	XAUDIO2_DEFAULT_PROCESSOR :: 1;
}
using XAUDIO2_PROCESSOR;


AUDIO_STREAM_CATEGORY :: enum {
  AudioCategory_Other;
  AudioCategory_ForegroundOnlyMedia;
  AudioCategory_BackgroundCapableMedia;
  AudioCategory_Communications;
  AudioCategory_Alerts;
  AudioCategory_SoundEffects;
  AudioCategory_GameEffects;
  AudioCategory_GameMedia;
  AudioCategory_GameChat;
  AudioCategory_Speech;
  AudioCategory_Movie;
  AudioCategory_Media;
  AudioCategory_FarFieldSpeech;
  AudioCategory_UniformSpeech;
  AudioCategory_VoiceTyping;
}
using AUDIO_STREAM_CATEGORY;


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


IXAudio2 :: struct {
	using vtable: *IXAudio2_VTable;
}


IXAudio2_VTable :: struct {
	using base: IUnknown_VTable;

	RegisterForCallbacks: (self: *IXAudio2, pCallback: *void) -> HRESULT #c_call;
	UnregisterForCallbacks: (self: *IXAudio2, pCallback: *void) #c_call;

	CreateSourceVoice: (
		self: *IXAudio2,
		ppSourceVoice: **IXAudio2SourceVoice,
		pSourceFormat: *WAVEFORMATEX,
		Flags: u32 = 0,
		MaxFrequencyRatio: float = 1.0,
		pCallback: *void = null,
		pSendList: *void = null,
		pEffectChain: *void = null
	) -> HRESULT #c_call;

	CreateSubmixVoice: (
		self: *IXAudio2,
		ppSubmixVoice: **void,
		InputChannels: u32,
		InputSampleRate: u32,
		Flags: u32 = 0,
		ProcessingStage: u32 = 0,
		pSendList: *void = null,
		pEffectChain: *void = null
	) -> HRESULT #c_call;

	CreateMasteringVoice: (
		self: *IXAudio2,
		ppMasteringVoice: **IXAudio2MasteringVoice,
		InputChannels: u32 = 0,
		InputSampleRate: u32 = 0,
		Flags: u32 = 0,
		szDeviceId: *u16 = null,
		pEffectChain: *void = null,
		StreamCategory := AudioCategory_GameEffects
	) -> HRESULT #c_call;

	// @TODO Add the rest of the stuff from this as needed

	/*
    // NAME: IXAudio2::RegisterForCallbacks
    // DESCRIPTION: Adds a new client to receive XAudio2's engine callbacks.
    //
    // ARGUMENTS:
    //  pCallback - Callback interface to be called during each processing pass.
    //
    STDMETHOD(RegisterForCallbacks) (_In_ IXAudio2EngineCallback* pCallback) PURE;

    // NAME: IXAudio2::UnregisterForCallbacks
    // DESCRIPTION: Removes an existing receiver of XAudio2 engine callbacks.
    //
    // ARGUMENTS:
    //  pCallback - Previously registered callback interface to be removed.
    //
    STDMETHOD_(void, UnregisterForCallbacks) (_In_ IXAudio2EngineCallback* pCallback) PURE;

    // NAME: IXAudio2::CreateSourceVoice
    // DESCRIPTION: Creates and configures a source voice.
    //
    // ARGUMENTS:
    //  ppSourceVoice - Returns the new object's IXAudio2SourceVoice interface.
    //  pSourceFormat - Format of the audio that will be fed to the voice.
    //  Flags - XAUDIO2_VOICE flags specifying the source voice's behavior.
    //  MaxFrequencyRatio - Maximum SetFrequencyRatio argument to be allowed.
    //  pCallback - Optional pointer to a client-provided callback interface.
    //  pSendList - Optional list of voices this voice should send audio to.
    //  pEffectChain - Optional list of effects to apply to the audio data.
    //
    STDMETHOD(CreateSourceVoice) (THIS_ _Outptr_ IXAudio2SourceVoice** ppSourceVoice,
                                  _In_ const WAVEFORMATEX* pSourceFormat,
                                  UINT32 Flags X2DEFAULT(0),
                                  float MaxFrequencyRatio X2DEFAULT(XAUDIO2_DEFAULT_FREQ_RATIO),
                                  _In_opt_ IXAudio2VoiceCallback* pCallback X2DEFAULT(NULL),
                                  _In_opt_ const XAUDIO2_VOICE_SENDS* pSendList X2DEFAULT(NULL),
                                  _In_opt_ const XAUDIO2_EFFECT_CHAIN* pEffectChain X2DEFAULT(NULL)) PURE;

    // NAME: IXAudio2::CreateSubmixVoice
    // DESCRIPTION: Creates and configures a submix voice.
    //
    // ARGUMENTS:
    //  ppSubmixVoice - Returns the new object's IXAudio2SubmixVoice interface.
    //  InputChannels - Number of channels in this voice's input audio data.
    //  InputSampleRate - Sample rate of this voice's input audio data.
    //  Flags - XAUDIO2_VOICE flags specifying the submix voice's behavior.
    //  ProcessingStage - Arbitrary number that determines the processing order.
    //  pSendList - Optional list of voices this voice should send audio to.
    //  pEffectChain - Optional list of effects to apply to the audio data.
    //
    STDMETHOD(CreateSubmixVoice) (THIS_ _Outptr_ IXAudio2SubmixVoice** ppSubmixVoice,
                                  UINT32 InputChannels, UINT32 InputSampleRate,
                                  UINT32 Flags X2DEFAULT(0), UINT32 ProcessingStage X2DEFAULT(0),
                                  _In_opt_ const XAUDIO2_VOICE_SENDS* pSendList X2DEFAULT(NULL),
                                  _In_opt_ const XAUDIO2_EFFECT_CHAIN* pEffectChain X2DEFAULT(NULL)) PURE;


    // NAME: IXAudio2::CreateMasteringVoice
    // DESCRIPTION: Creates and configures a mastering voice.
    //
    // ARGUMENTS:
    //  ppMasteringVoice - Returns the new object's IXAudio2MasteringVoice interface.
    //  InputChannels - Number of channels in this voice's input audio data.
    //  InputSampleRate - Sample rate of this voice's input audio data.
    //  Flags - XAUDIO2_VOICE flags specifying the mastering voice's behavior.
    //  szDeviceId - Identifier of the device to receive the output audio.
    //  pEffectChain - Optional list of effects to apply to the audio data.
    //  StreamCategory - The audio stream category to use for this mastering voice
    //
    STDMETHOD(CreateMasteringVoice) (THIS_ _Outptr_ IXAudio2MasteringVoice** ppMasteringVoice,
                                     UINT32 InputChannels X2DEFAULT(XAUDIO2_DEFAULT_CHANNELS),
                                     UINT32 InputSampleRate X2DEFAULT(XAUDIO2_DEFAULT_SAMPLERATE),
                                     UINT32 Flags X2DEFAULT(0), _In_opt_z_ LPCWSTR szDeviceId X2DEFAULT(NULL),
                                     _In_opt_ const XAUDIO2_EFFECT_CHAIN* pEffectChain X2DEFAULT(NULL),
                                    _In_ AUDIO_STREAM_CATEGORY StreamCategory X2DEFAULT(AudioCategory_GameEffects)) PURE;

    // NAME: IXAudio2::StartEngine
    // DESCRIPTION: Creates and starts the audio processing thread.
    //
    STDMETHOD(StartEngine) (THIS) PURE;

    // NAME: IXAudio2::StopEngine
    // DESCRIPTION: Stops and destroys the audio processing thread.
    //
    STDMETHOD_(void, StopEngine) (THIS) PURE;

    // NAME: IXAudio2::CommitChanges
    // DESCRIPTION: Atomically applies a set of operations previously tagged
    //              with a given identifier.
    //
    // ARGUMENTS:
    //  OperationSet - Identifier of the set of operations to be applied.
    //
    STDMETHOD(CommitChanges) (THIS_ UINT32 OperationSet) PURE;

    // NAME: IXAudio2::GetPerformanceData
    // DESCRIPTION: Returns current resource usage details: memory, CPU, etc.
    //
    // ARGUMENTS:
    //  pPerfData - Returns the performance data structure.
    //
    STDMETHOD_(void, GetPerformanceData) (THIS_ _Out_ XAUDIO2_PERFORMANCE_DATA* pPerfData) PURE;

    // NAME: IXAudio2::SetDebugConfiguration
    // DESCRIPTION: Configures XAudio2's debug output (in debug builds only).
    //
    // ARGUMENTS:
    //  pDebugConfiguration - Structure describing the debug output behavior.
    //  pReserved - Optional parameter; must be NULL.
    //
    STDMETHOD_(void, SetDebugConfiguration) (THIS_ _In_opt_ const XAUDIO2_DEBUG_CONFIGURATION* pDebugConfiguration,
                                             _Reserved_ void* pReserved X2DEFAULT(NULL)) PURE;
	*/
}


IXAudio2Voice :: struct {
	using vtable: *IXAudio2Voice_VTable;
}


IXAudio2Voice_VTable :: struct {
	GetVoiceDetails: *void;
	SetOutputVoices: *void;
	SetEffectChain: *void;
	EnableEffect: *void;
	DisableEffect: *void;
	GetEffectState: *void;
	SetEffectParameters: *void;
	GetEffectParameters: *void;
	SetFilterParameters: *void;
	GetFilterParameters: *void;
	SetOutputFilterParameters: *void;
	GetOutputFilterParameters: *void;
	SetVolume: *void;
	GetVolume: *void;
	SetChannelVolumes: *void;
	GetChannelVolumes: *void;
	SetOutputMatrix: *void;
	GetOutputMatrix: *void;
	DestroyVoice: *void;

	/*
    /* NAME: IXAudio2Voice::GetVoiceDetails
    // DESCRIPTION: Returns the basic characteristics of this voice.
    //
    // ARGUMENTS:
    //  pVoiceDetails - Returns the voice's details.
    */\
    STDMETHOD_(void, GetVoiceDetails) (THIS_ _Out_ XAUDIO2_VOICE_DETAILS* pVoiceDetails) PURE; \
    \
    /* NAME: IXAudio2Voice::SetOutputVoices
    // DESCRIPTION: Replaces the set of submix/mastering voices that receive
    //              this voice's output.
    //
    // ARGUMENTS:
    //  pSendList - Optional list of voices this voice should send audio to.
    */\
    STDMETHOD(SetOutputVoices) (THIS_ _In_opt_ const XAUDIO2_VOICE_SENDS* pSendList) PURE; \
    \
    /* NAME: IXAudio2Voice::SetEffectChain
    // DESCRIPTION: Replaces this voice's current effect chain with a new one.
    //
    // ARGUMENTS:
    //  pEffectChain - Structure describing the new effect chain to be used.
    */\
    STDMETHOD(SetEffectChain) (THIS_ _In_opt_ const XAUDIO2_EFFECT_CHAIN* pEffectChain) PURE; \
    \
    /* NAME: IXAudio2Voice::EnableEffect
    // DESCRIPTION: Enables an effect in this voice's effect chain.
    //
    // ARGUMENTS:
    //  EffectIndex - Index of an effect within this voice's effect chain.
    //  OperationSet - Used to identify this call as part of a deferred batch.
    */\
    STDMETHOD(EnableEffect) (THIS_ UINT32 EffectIndex, \
                             UINT32 OperationSet X2DEFAULT(XAUDIO2_COMMIT_NOW)) PURE; \
    \
    /* NAME: IXAudio2Voice::DisableEffect
    // DESCRIPTION: Disables an effect in this voice's effect chain.
    //
    // ARGUMENTS:
    //  EffectIndex - Index of an effect within this voice's effect chain.
    //  OperationSet - Used to identify this call as part of a deferred batch.
    */\
    STDMETHOD(DisableEffect) (THIS_ UINT32 EffectIndex, \
                              UINT32 OperationSet X2DEFAULT(XAUDIO2_COMMIT_NOW)) PURE; \
    \
    /* NAME: IXAudio2Voice::GetEffectState
    // DESCRIPTION: Returns the running state of an effect.
    //
    // ARGUMENTS:
    //  EffectIndex - Index of an effect within this voice's effect chain.
    //  pEnabled - Returns the enabled/disabled state of the given effect.
    */\
    STDMETHOD_(void, GetEffectState) (THIS_ UINT32 EffectIndex, _Out_ BOOL* pEnabled) PURE; \
    \
    /* NAME: IXAudio2Voice::SetEffectParameters
    // DESCRIPTION: Sets effect-specific parameters.
    //
    // REMARKS: Unlike IXAPOParameters::SetParameters, this method may
    //          be called from any thread.  XAudio2 implements
    //          appropriate synchronization to copy the parameters to the
    //          realtime audio processing thread.
    //
    // ARGUMENTS:
    //  EffectIndex - Index of an effect within this voice's effect chain.
    //  pParameters - Pointer to an effect-specific parameters block.
    //  ParametersByteSize - Size of the pParameters array  in bytes.
    //  OperationSet - Used to identify this call as part of a deferred batch.
    */\
    STDMETHOD(SetEffectParameters) (THIS_ UINT32 EffectIndex, \
                                    _In_reads_bytes_(ParametersByteSize) const void* pParameters, \
                                    UINT32 ParametersByteSize, \
                                    UINT32 OperationSet X2DEFAULT(XAUDIO2_COMMIT_NOW)) PURE; \
    \
    /* NAME: IXAudio2Voice::GetEffectParameters
    // DESCRIPTION: Obtains the current effect-specific parameters.
    //
    // ARGUMENTS:
    //  EffectIndex - Index of an effect within this voice's effect chain.
    //  pParameters - Returns the current values of the effect-specific parameters.
    //  ParametersByteSize - Size of the pParameters array in bytes.
    */\
    STDMETHOD(GetEffectParameters) (THIS_ UINT32 EffectIndex, \
                                    _Out_writes_bytes_(ParametersByteSize) void* pParameters, \
                                    UINT32 ParametersByteSize) PURE; \
    \
    /* NAME: IXAudio2Voice::SetFilterParameters
    // DESCRIPTION: Sets this voice's filter parameters.
    //
    // ARGUMENTS:
    //  pParameters - Pointer to the filter's parameter structure.
    //  OperationSet - Used to identify this call as part of a deferred batch.
    */\
    STDMETHOD(SetFilterParameters) (THIS_ _In_ const XAUDIO2_FILTER_PARAMETERS* pParameters, \
                                    UINT32 OperationSet X2DEFAULT(XAUDIO2_COMMIT_NOW)) PURE; \
    \
    /* NAME: IXAudio2Voice::GetFilterParameters
    // DESCRIPTION: Returns this voice's current filter parameters.
    //
    // ARGUMENTS:
    //  pParameters - Returns the filter parameters.
    */\
    STDMETHOD_(void, GetFilterParameters) (THIS_ _Out_ XAUDIO2_FILTER_PARAMETERS* pParameters) PURE; \
    \
    /* NAME: IXAudio2Voice::SetOutputFilterParameters
    // DESCRIPTION: Sets the filter parameters on one of this voice's sends.
    //
    // ARGUMENTS:
    //  pDestinationVoice - Destination voice of the send whose filter parameters will be set.
    //  pParameters - Pointer to the filter's parameter structure.
    //  OperationSet - Used to identify this call as part of a deferred batch.
    */\
    STDMETHOD(SetOutputFilterParameters) (THIS_ _In_opt_ IXAudio2Voice* pDestinationVoice, \
                                          _In_ const XAUDIO2_FILTER_PARAMETERS* pParameters, \
                                          UINT32 OperationSet X2DEFAULT(XAUDIO2_COMMIT_NOW)) PURE; \
    \
    /* NAME: IXAudio2Voice::GetOutputFilterParameters
    // DESCRIPTION: Returns the filter parameters from one of this voice's sends.
    //
    // ARGUMENTS:
    //  pDestinationVoice - Destination voice of the send whose filter parameters will be read.
    //  pParameters - Returns the filter parameters.
    */\
    STDMETHOD_(void, GetOutputFilterParameters) (THIS_ _In_opt_ IXAudio2Voice* pDestinationVoice, \
                                                 _Out_ XAUDIO2_FILTER_PARAMETERS* pParameters) PURE; \
    \
    /* NAME: IXAudio2Voice::SetVolume
    // DESCRIPTION: Sets this voice's overall volume level.
    //
    // ARGUMENTS:
    //  Volume - New overall volume level to be used, as an amplitude factor.
    //  OperationSet - Used to identify this call as part of a deferred batch.
    */\
    STDMETHOD(SetVolume) (THIS_ float Volume, \
                          UINT32 OperationSet X2DEFAULT(XAUDIO2_COMMIT_NOW)) PURE; \
    \
    /* NAME: IXAudio2Voice::GetVolume
    // DESCRIPTION: Obtains this voice's current overall volume level.
    //
    // ARGUMENTS:
    //  pVolume: Returns the voice's current overall volume level.
    */\
    STDMETHOD_(void, GetVolume) (THIS_ _Out_ float* pVolume) PURE; \
    \
    /* NAME: IXAudio2Voice::SetChannelVolumes
    // DESCRIPTION: Sets this voice's per-channel volume levels.
    //
    // ARGUMENTS:
    //  Channels - Used to confirm the voice's channel count.
    //  pVolumes - Array of per-channel volume levels to be used.
    //  OperationSet - Used to identify this call as part of a deferred batch.
    */\
    STDMETHOD(SetChannelVolumes) (THIS_ UINT32 Channels, _In_reads_(Channels) const float* pVolumes, \
                                  UINT32 OperationSet X2DEFAULT(XAUDIO2_COMMIT_NOW)) PURE; \
    \
    /* NAME: IXAudio2Voice::GetChannelVolumes
    // DESCRIPTION: Returns this voice's current per-channel volume levels.
    //
    // ARGUMENTS:
    //  Channels - Used to confirm the voice's channel count.
    //  pVolumes - Returns an array of the current per-channel volume levels.
    */\
    STDMETHOD_(void, GetChannelVolumes) (THIS_ UINT32 Channels, _Out_writes_(Channels) float* pVolumes) PURE; \
    \
    /* NAME: IXAudio2Voice::SetOutputMatrix
    // DESCRIPTION: Sets the volume levels used to mix from each channel of this
    //              voice's output audio to each channel of a given destination
    //              voice's input audio.
    //
    // ARGUMENTS:
    //  pDestinationVoice - The destination voice whose mix matrix to change.
    //  SourceChannels - Used to confirm this voice's output channel count
    //   (the number of channels produced by the last effect in the chain).
    //  DestinationChannels - Confirms the destination voice's input channels.
    //  pLevelMatrix - Array of [SourceChannels * DestinationChannels] send
    //   levels.  The level used to send from source channel S to destination
    //   channel D should be in pLevelMatrix[S + SourceChannels * D].
    //  OperationSet - Used to identify this call as part of a deferred batch.
    */\
    STDMETHOD(SetOutputMatrix) (THIS_ _In_opt_ IXAudio2Voice* pDestinationVoice, \
                                UINT32 SourceChannels, UINT32 DestinationChannels, \
                                _In_reads_(SourceChannels * DestinationChannels) const float* pLevelMatrix, \
                                UINT32 OperationSet X2DEFAULT(XAUDIO2_COMMIT_NOW)) PURE; \
    \
    /* NAME: IXAudio2Voice::GetOutputMatrix
    // DESCRIPTION: Obtains the volume levels used to send each channel of this
    //              voice's output audio to each channel of a given destination
    //              voice's input audio.
    //
    // ARGUMENTS:
    //  pDestinationVoice - The destination voice whose mix matrix to obtain.
    //  SourceChannels - Used to confirm this voice's output channel count
    //   (the number of channels produced by the last effect in the chain).
    //  DestinationChannels - Confirms the destination voice's input channels.
    //  pLevelMatrix - Array of send levels, as above.
    */\
    STDMETHOD_(void, GetOutputMatrix) (THIS_ _In_opt_ IXAudio2Voice* pDestinationVoice, \
                                       UINT32 SourceChannels, UINT32 DestinationChannels, \
                                       _Out_writes_(SourceChannels * DestinationChannels) float* pLevelMatrix) PURE; \
    \
    /* NAME: IXAudio2Voice::DestroyVoice
    // DESCRIPTION: Destroys this voice, stopping it if necessary and removing
    //              it from the XAudio2 graph.
    */\
    STDMETHOD_(void, DestroyVoice) (THIS) PURE
	*/
}

IXAudio2MasteringVoice :: struct {
	using vtable: *IXAudio2MasteringVoice_VTable;
}


IXAudio2MasteringVoice_VTable :: struct {
	using base: IXAudio2Voice_VTable;
	GetChannelMask: *void;
}


IXAudio2SourceVoice :: struct {
	using vtable: *IXAudio2SourceVoice_VTable;
}


IXAudio2SourceVoice_VTable :: struct {
	using base: IXAudio2Voice_VTable;	

	Start: (
		self: *IXAudio2SourceVoice,
		Flags: u32 = 0,
		OperationSet: u32 = XAUDIO2_COMMIT_NOW
	) -> HRESULT #c_call;

	Stop: *void;

	SubmitSourceBuffer: (
		self: *IXAudio2SourceVoice,
		pBuffer: *XAUDIO2_BUFFER,
		pBufferWMA: *void = null
	) -> HRESULT #c_call;

	FlushSourceBuffers: (self: *IXAudio2SourceVoice) -> HRESULT #c_call;
	
	Discontinuity: (self: *IXAudio2SourceVoice) -> HRESULT #c_call;

	ExitLoop: *void;
	GetState: *void;
	SetFrequencyRatio: *void;
	GetFrequencyRatio: *void;
	SetSourceSampleRate: *void;
		
	/*
    // NAME: IXAudio2SourceVoice::Start
    // DESCRIPTION: Makes this voice start consuming and processing audio.
    //
    // ARGUMENTS:
    //  Flags - Flags controlling how the voice should be started.
    //  OperationSet - Used to identify this call as part of a deferred batch.
    //
    STDMETHOD(Start) (THIS_ UINT32 Flags X2DEFAULT(0), UINT32 OperationSet X2DEFAULT(XAUDIO2_COMMIT_NOW)) PURE;

    // NAME: IXAudio2SourceVoice::Stop
    // DESCRIPTION: Makes this voice stop consuming audio.
    //
    // ARGUMENTS:
    //  Flags - Flags controlling how the voice should be stopped.
    //  OperationSet - Used to identify this call as part of a deferred batch.
    //
    STDMETHOD(Stop) (THIS_ UINT32 Flags X2DEFAULT(0), UINT32 OperationSet X2DEFAULT(XAUDIO2_COMMIT_NOW)) PURE;

    // NAME: IXAudio2SourceVoice::SubmitSourceBuffer
    // DESCRIPTION: Adds a new audio buffer to this voice's input queue.
    //
    // ARGUMENTS:
    //  pBuffer - Pointer to the buffer structure to be queued.
    //  pBufferWMA - Additional structure used only when submitting XWMA data.
    //
    STDMETHOD(SubmitSourceBuffer) (THIS_ _In_ const XAUDIO2_BUFFER* pBuffer, _In_opt_ const XAUDIO2_BUFFER_WMA* pBufferWMA X2DEFAULT(NULL)) PURE;

    // NAME: IXAudio2SourceVoice::FlushSourceBuffers
    // DESCRIPTION: Removes all pending audio buffers from this voice's queue.
    //
    STDMETHOD(FlushSourceBuffers) (THIS) PURE;

    // NAME: IXAudio2SourceVoice::Discontinuity
    // DESCRIPTION: Notifies the voice of an intentional break in the stream of
    //              audio buffers (e.g. the end of a sound), to prevent XAudio2
    //              from interpreting an empty buffer queue as a glitch.
    //
    STDMETHOD(Discontinuity) (THIS) PURE;

    // NAME: IXAudio2SourceVoice::ExitLoop
    // DESCRIPTION: Breaks out of the current loop when its end is reached.
    //
    // ARGUMENTS:
    //  OperationSet - Used to identify this call as part of a deferred batch.
    //
    STDMETHOD(ExitLoop) (THIS_ UINT32 OperationSet X2DEFAULT(XAUDIO2_COMMIT_NOW)) PURE;

    // NAME: IXAudio2SourceVoice::GetState
    // DESCRIPTION: Returns the number of buffers currently queued on this voice,
    //              the pContext value associated with the currently processing
    //              buffer (if any), and other voice state information.
    //
    // ARGUMENTS:
    //  pVoiceState - Returns the state information.
    //  Flags - Flags controlling what voice state is returned.
    //
    STDMETHOD_(void, GetState) (THIS_ _Out_ XAUDIO2_VOICE_STATE* pVoiceState, UINT32 Flags X2DEFAULT(0)) PURE;

    // NAME: IXAudio2SourceVoice::SetFrequencyRatio
    // DESCRIPTION: Sets this voice's frequency adjustment, i.e. its pitch.
    //
    // ARGUMENTS:
    //  Ratio - Frequency change, expressed as source frequency / target frequency.
    //  OperationSet - Used to identify this call as part of a deferred batch.
    //
    STDMETHOD(SetFrequencyRatio) (THIS_ float Ratio,
                                  UINT32 OperationSet X2DEFAULT(XAUDIO2_COMMIT_NOW)) PURE;

    // NAME: IXAudio2SourceVoice::GetFrequencyRatio
    // DESCRIPTION: Returns this voice's current frequency adjustment ratio.
    //
    // ARGUMENTS:
    //  pRatio - Returns the frequency adjustment.
    //
    STDMETHOD_(void, GetFrequencyRatio) (THIS_ _Out_ float* pRatio) PURE;

    // NAME: IXAudio2SourceVoice::SetSourceSampleRate
    // DESCRIPTION: Reconfigures this voice to treat its source data as being
    //              at a different sample rate than the original one specified
    //              in CreateSourceVoice's pSourceFormat argument.
    //
    // ARGUMENTS:
    //  UINT32 - The intended sample rate of further submitted source data.
    //
    STDMETHOD(SetSourceSampleRate) (THIS_ UINT32 NewSourceSampleRate) PURE;
	*/
}


XAUDIO2_BUFFER :: struct {
	Flags: u32;
	AudioBytes: u32;
	pAudioData: *u8;
	PlayBegin: u32;
	PlayLength: u32;
	LoopBegin: u32;
	LoopLength: u32;
	LoopCount: u32;
	pContext: *void;
}

XAUDIO2_END_OF_STREAM :: 0x0040;    // Used in XAUDIO2_BUFFER.Flags
XAUDIO2_LOOP_INFINITE :: 255;       // Used in XAUDIO2_BUFFER.LoopCount
XAUDIO2_COMMIT_NOW :: 0;             // Used as an OperationSet argument
