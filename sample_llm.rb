# require_relative 'glauco-framework'
require 'ruby_llm'

MODEL_ROOT_FOLDER = "vendor"
MODEL_OPTIONS = [
  {
    file: File.join(MODEL_ROOT_FOLDER, "gemma-3n-E4B-it-Q4_K_M.gguf"),
    identifier: "gemma-3n-e4b-it-text",
  }
]
LMS_EXE_PATH = File.join(ENV['USERPROFILE'] || ENV['HOME'], ".lmstudio", "bin", "lms.exe")
LMSTUDIO_EXE = "vendor\\LM Studio\\LM Studio.exe"
MODEL_PATH = MODEL_OPTIONS[0][:file]
MODEL_IDENTIFIER = MODEL_OPTIONS[0][:identifier]
SERVER_PORT = "1234"

unless File.exist?(LMS_EXE_PATH)
  puts "Starting LM Studio headless..."
  system("#{LMSTUDIO_EXE} --headless")
end

runtime_src  = File.join("vendor", ".lmstudio")
runtime_dest = File.join(Dir.home, ".lmstudio")

unless Dir.exist?(runtime_dest)
  puts "Copying runtime to #{runtime_dest}..."
  FileUtils.mkdir_p(File.dirname(runtime_dest))
  FileUtils.cp_r(runtime_src, runtime_dest)
end

puts "Importing model..."
system("#{LMS_EXE_PATH} import #{MODEL_PATH} -y --hard-link")
puts "Loading model..."
system("#{LMS_EXE_PATH} load #{MODEL_IDENTIFIER} -y --identifier #{MODEL_IDENTIFIER}")
puts "Starting LM Studio server... #{LMS_EXE_PATH}"
spawn(LMS_EXE_PATH, "server", "start", "--port", SERVER_PORT, out: $stdout, err: $stderr)
sleep 3 # aguarda servidor iniciar

RubyLLM.configure do |config|
  config.openai_api_key = 'none'  
  config.openai_api_base = "http://127.0.0.1:#{SERVER_PORT}/v1"  
end

chat = RubyLLM.chat(model: 'gemma-3n-e4b-it-text', provider: :openai, assume_model_exists: true)

#  Registro de tools chat.with_tool()
chat.with_instructions ""

class Weather < RubyLLM::Tool
  description "Gets current weather for a location"
  param :latitude, desc: "Latitude (e.g., 52.5200)"
  param :longitude, desc: "Longitude (e.g., 13.4050)"

  def execute(latitude:, longitude:)
    url = "https://api.open-meteo.com/v1/forecast?latitude=#{latitude}&longitude=#{longitude}&current=temperature_2m,wind_speed_10m"

    response = Faraday.get(url)
    data = JSON.parse(response.body)
  rescue => e
    { error: e.message }
  end
end

chat.with_tool(Weather)

chat.ask  "What's the current weather in Berlin, Germany?" do |chunk|
  print chunk.content # Print content fragment immediately
end
