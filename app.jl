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
    headers = ["Authorization" => "Bearer $(get(ENV, "OPENAI_API_KEY", ""))"]
    f = open(file)
    form = HTTP.Forms.Form(Dict("file" => f, "model" => "whisper-1"))
    response = HTTP.post(url, headers, form, status_exception = false)
    transcription = response.status == 200 ? JSON3.read(response.body)["text"] : JSON3.read(response.body)[:error][:message]
    close(f)
    return transcription
end

@app begin
    @in input = ""
    @in mediaRecorder = nothing
    @in is_recording = false
    @in show_uploader = false
    @in clear_input = false
    @out audio_chunks = []
    
    @onchange isready begin
        @info "I am alive!"
    end

    @onbutton clear_input begin
        input = ""
    end

    @event uploaded begin
        @info "Event :uploaded\n$event"
        @notify """File(s) '$(join([f["name"] for f in event["files"]], "', '"))' uploaded!"""
    end

    @onchange fileuploads begin
        isempty(fileuploads) && return
        @info "File was uploaded: " fileuploads["path"]
        try
            fn_new = fileuploads["path"] * ".wav"
            mv(fileuploads["path"], fn_new; force = true)
            input = strip(input * " " * openai_whisper(fn_new))
            rm(fn_new; force = true)
        catch e
            @error "Error processing file: $e"
            notify(__model__, "Error processing file: $(fileuploads["name"])")
            "FAIL!"
        end
        @run raw"this.$refs.uploader.reset()"
        audio_chunks = []
        empty!(fileuploads)
    end
end

@client_data begin
    channel_ = ""
end

# add a toJSON method for File objects
@mounted """
File.prototype.toJSON = function() {
    return {
        lastModified: this.lastModified,
        name: this.name,
        size: this.size,
        type: this.type,
        webkitRelativePath: this.webkitRelativePath
    };
}
"""

function ui()
    [
        h3("Speech-to-text API")

        row(class = "q-mt-xl", [
            btn(@click("toggleRecording"),
                # label = R"is_recording ? 'Stop' : 'Record'",
                icon = R"is_recording ? 'mic_off' : 'mic'",
                color = R"is_recording ? 'negative' : 'primary'"
            )

            btn(class = "q-ml-lg", @click(:clear_input), icon = "delete_forever", color = "primary")
            
            toggle(class = "q-ml-lg", "Show uploader", :show_uploader)
        ])
        
        textfield(class = "q-mt-lg", "Input", :input, type = "textarea", :standout)

        uploader("", class = "q-mt-lg",
            label = "Audio Upload",
            autoupload = true,
            hideuploadbtn = true,
            nothumbnails = true,
            @showif("show_uploader"),
            @on(:uploaded, :uploaded),
            ref = "uploader"
        )
    ] |> htmldiv # wrap in htmldiv in order to avoid stipplecore formatting of first-level rows
end

@methods raw"""
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
            this.mediaRecorder = new MediaRecorder(stream);
            this.mediaRecorder.onstart = () => { this.is_recording = true };
            this.mediaRecorder.onstop = () => { this.is_recording = false };
            this.mediaRecorder.start();
            this.mediaRecorder.ondataavailable = event => {
                console.log('data available: ', event.data.size, 'bytes');
                this.audio_chunks.push(event.data);
                const audioBlob = new Blob(this.audio_chunks, { type: 'audio/wav' });
                
                // upload via uploader
                const filename = 'audio.wav';
                const file = new File([audioBlob], filename);
                this.$refs.uploader.addFiles([file]);
                // this.$refs.uploader.upload(); // not necessary as auto-upload is enabled
                console.log(`Uploading audio as '${filename}' ...`);
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

@page("/", ui)

up(open_browser = true)

end
