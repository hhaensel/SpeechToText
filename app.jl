module App
using GenieFramework
using GenieFramework.JSON3
using GenieFramework.Stipple.HTTP
using GenieFramework.Stipple.ModelStorage.Sessions# for @init
using Base64
@genietools

@appname Recorder

function openai_whisper(file)
    url = "https://api.openai.com/v1/audio/transcriptions"
    headers = ["Authorization" => "Bearer $(ENV["OPENAI_API_KEY"])"]
    form = HTTP.Forms.Form(Dict(
        "file" => open(file), "model" => "whisper-1"))
    response = HTTP.post(url, headers, form)
    transcription = JSON3.read(response.body)["text"]
    return transcription
end

@app begin
    @in input = "Record some audio to see the transcript here."
    @in audio_chunks = []
    @in mediaRecorder = nothing
    @in is_recording = false
    @onchange isready begin
        @info "I am alive!"
    end
    @event uploaded begin
        @info "File uploaded!!"
        @info params(:payload)["event"]
        notify(__model__, "File uploaded!")
    end
    @onchange fileuploads begin
        if !isempty(fileuploads)
            @info "File was uploaded: " fileuploads["path"]
            filename = base64encode(fileuploads["name"])
            try
                fn_new = fileuploads["path"] * ".wav"
                mv(fileuploads["path"], fn_new; force = true)
                input = openai_whisper(fn_new)
                rm(fn_new; force = true)
            catch e
                @error "Error processing file: $e"
                notify(__model__, "Error processing file: $(fileuploads["name"])")
                "FAIL!"
            end
            fileuploads = Dict{AbstractString, AbstractString}()
        end
    end
end

function ui()
    [
        h3("Speech-to-text API"),
        h6("Transcript: "),
        card(p("{{input}}")),
        btn(@click("toggleRecording"),
            label = R"is_recording ? 'Stop' : 'Record'",
            color = R"is_recording ? 'negative' : 'primary'"
        ),
        uploader(multiple = false,
            maxfiles = 10,
            autoupload = true,
            hideuploadbtn = true,
            label = "Upload",
            nothumbnails = true,
            ref = "uploader",
            style = "display: none; visibility: hidden;",
            @on("uploaded", :uploaded)
        )
    ]
end

@methods begin
    raw"""
    async toggleRecording() {
        if (!this.is_recording) {
          this.startRecording()
        } else {
          this.stopRecording()
        }
    },
    async startRecording() {
      navigator.mediaDevices.getUserMedia({ audio: true })
        .then(stream => {
          this.is_recording = true
          this.mediaRecorder = new MediaRecorder(stream);
          this.mediaRecorder.start();
          this.mediaRecorder.onstop = () => {
            const audioBlob = new Blob(this.audio_chunks, { type: 'audio/wav' });
            this.is_recording = false;

            // upload via uploader
            const file = new File([audioBlob], 'test.wav');
            this.$refs.uploader.addFiles([file], 'test.wav');
            this.$refs.uploader.upload(); // Trigger the upload
            console.log("Uploaded WAV");
            this.$refs.uploader.reset();
            this.audio_chunks=[];

          };
          this.mediaRecorder.ondataavailable = event => {
            this.audio_chunks.push(event.data);
          };
        })
        .catch(error => console.error('Error accessing microphone:', error));
    },
    stopRecording() {
      if (this.mediaRecorder) {
        this.mediaRecorder.stop();
      } else {
        console.error('MediaRecorder is not initialized');
      }
    }
"""
end

@page("/",ui())


end
