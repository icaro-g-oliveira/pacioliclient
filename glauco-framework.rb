require 'java'
require './jarlibs/swt.jar'

java_import 'org.eclipse.swt.widgets.Display'
java_import 'org.eclipse.swt.widgets.Shell'
java_import 'org.eclipse.swt.layout.FillLayout'
java_import 'org.eclipse.swt.browser.Browser'
java_import 'org.eclipse.swt.browser.BrowserFunction'
java_import 'org.eclipse.swt.widgets.FileDialog'
java_import 'org.eclipse.swt.SWT'
java_import 'java.awt.Toolkit'
java_import 'java.awt.datatransfer.DataFlavor'
java_import 'org.eclipse.swt.dnd.Clipboard'
java_import 'org.eclipse.swt.dnd.TextTransfer'
java_import 'org.eclipse.swt.browser.ProgressAdapter'
java_import 'org.eclipse.swt.browser.ProgressEvent'
java_import 'org.eclipse.swt.browser.LocationAdapter'
java_import 'org.eclipse.swt.events.ShellListener'
java_import 'org.eclipse.swt.widgets.Listener'

require 'json'
require 'fileutils'
require 'open3'
require 'securerandom'
require 'ruby_llm'


module Frontend
  $callbacks = {}

  def async(&block)
    $display.async_exec do
      block.call
    end
  end

  def browserFunctionFac(callback_name)
    Class.new(Java::OrgEclipseSwtBrowser::BrowserFunction) do
      define_method(:function) do |*args|
        begin
          puts callback_name+" called with args "+ args.to_a[0].to_s
          $callbacks[callback_name].call(args.to_a[0])
        rescue => e
          puts "Error in callback #{callback_name}: #{e.class} - #{e.message}"
        end 
      end
    end.new($browser, callback_name)
  end

  def getClipBoardText
    java.awt.Toolkit.getDefaultToolkit.getSystemClipboard.getData(
      java.awt.datatransfer.DataFlavor.stringFlavor
    )
  end

  class RootRenderer
    attr_accessor :browser, :callbacks, :root_component

    def initialize(browser)
      @browser = browser
    end
    
    def bind_callback(event, proc_obj)
      callback_name = "callback_#{rand(1000..9999)}"
      $callbacks[callback_name] = proc_obj
      if @browser
        browserFunctionFac(callback_name)
      end

      # Retorna o atributo HTML correto
      "#{event.to_s.gsub('_', '')}=\"#{callback_name}(this.value)\""
    end
    def render
      puts "calling render"
      return unless @root_component
      puts "passed root_component condition"
      puts "now will call browser.set_text"
      puts "HTML content: #{@root_component.render_to_html}"
      @browser.set_text(@root_component.render_to_html)
    end

    def update_dom(placeholder_id, new_html)
      # garanta string
      html_str = new_html.is_a?(String) ? new_html : Array(new_html).join
      puts "updated dom #{placeholder_id}"
      puts "html_str: #{html_str}"
      js = <<~JS
        (function(){
          var el = document.getElementById("#{placeholder_id}");
          if (el) {
            el.innerHTML = #{html_str.to_json};
          }
        })();
      JS
      @browser.evaluate(js)
    end
  end

  private
  public
  class Component
    attr_accessor :state, :children, :parent_renderer, :attrs

    def initialize(parent_renderer: nil, **attrs)
      puts "initilizing component"
      @state = {}
      @bindings = []
      @children = []
      @parent_renderer = parent_renderer
      @event_listeners = {}
      @attrs = self.class.default_attrs.merge(attrs)
    end

    undef select

    class << self
      def attrs(defaults = {})
        @default_attrs = defaults
        self
      end

      def default_attrs
        @default_attrs || {}
      end
    end

    def add_event_listener(event_name, &callback)
      callback_name = "callback_#{$callbacks.length+1}"
      $callbacks[callback_name] = callback
      if @parent_renderer&.browser
        browserFunctionFac(callback_name)
      end
    end
        
    
    # Define o método _ que inicializa um StatePath a partir de Symbol
    class Symbol
      def >(other)
        sp = StatePath.new(self)
        sp.append_part(other)
      end
    end

    # Classe StatePath
    class StatePath
      def initialize(base)
        @parts = [base.to_s]
      end

      def [](key)
        @parts << key.to_s
        self
      end

      def to_s
        first, *rest = @parts
        rest.reduce(first) { |acc, part| "#{acc}[#{part}]" }
      end
    end


    # --- Bindings avançados ---
    def bind(state_key, node, &block)
      # garante que sempre temos um StatePath
      puts "binding #{state_key} to node #{node}"
      state_path = state_key.is_a?(StatePath) ? state_key : StatePath.new(state_key)

      path_str = state_path.to_s
      puts "path_str: #{path_str}"

      # injeta data-bind no HTML
      node = node.sub(/<(\w+)([^>]*)>/, "<\\1\\2 data-bind=\"#{path_str}\">")
      puts "node after data-bind injection: #{node}"

      # registra o binding
      @bindings << { path: state_path, key: path_str, block: block }
      puts "registered bindings: #{@bindings}"

      # busca valor atual
      value = dig_state_path(state_path)
      puts "current value for #{path_str}: #{value.inspect}"

      begin
        puts "current value for #{path_str}: #{value.inspect}"
        result = block.call(value)

        inner_html =
          case result
          when Array
            result.map { |r| r.is_a?(Component) ? r.render_to_html : r.to_s }.join
          when Component
            result.render_to_html
          else
            result.to_s
          end
      rescue => e
        puts "⚠️ Erro ao executar binding para #{path_str}: #{e.class} - #{e.message}"
        inner_html = ""
      end

      puts "inner_html: #{inner_html}"
      node = node.sub(%r{</\w+>}, inner_html + '\0')
      puts "node after inner_html injection: #{node}"

      node
    end

    def dig_state_path(state_path)
      puts "dig_state_path called with #{state_path}"
      parts = state_path.to_s.scan(/([^\[\]]+)/).flatten
      parts.reduce(@state) do |obj, key|
        break nil if obj.nil?

        if obj.is_a?(Array)
          puts "Accessing array with key #{key}"
          idx = key.to_i rescue nil
          break nil if idx.nil?
          obj[idx]
        elsif obj.is_a?(Hash)
          puts "Accessing hash with key #{key}"
          key_sym = key.to_sym
          if obj.key?(key_sym)
            puts "Found key #{key_sym} in hash"
            obj[key_sym]
          elsif obj.key?(key)
            puts "Found key #{key} in hash"
            obj[key]
          else
            nil
          end
        else
          nil
        end
      end
    end


    # --- Atualização de estado com paths complexos ---
    def set_state(path, new_value)
      path_str = path.is_a?(StatePath) ? path.to_s : path.to_s
      puts "set_state called with path #{path_str} and value #{new_value.inspect}"

      parts = path_str.split(/[:\[\]]/).reject(&:empty?)
      last_key = parts.pop
      target = parts.reduce(@state) do |obj, key|
        if obj[key.to_sym].nil?
          obj[key.to_sym] = {}
        end
        obj[key.to_sym]
      end

      target[last_key.to_sym] = new_value

      notify_bindings(path)
    end

    # --- Notificação de bindings ---
    def notify_bindings(path)
      path_str = path.is_a?(StatePath) ? path.to_s : path.to_s
      puts "notify_bindings called for path #{path_str}"

      @bindings.each do |binding|
        binding_path_str = binding[:path].to_s

        # verifica se binding é afetado: match exato ou prefixo
        if path_str == binding_path_str || binding_path_str.start_with?("#{path_str}:") || binding_path_str.start_with?("#{path_str}[")
          value = dig_state_path(binding[:path])
          puts "Binding found for #{binding_path_str}, updating DOM with value: #{value.inspect}"

          begin
            puts "Calling binding block for #{binding_path_str} with value #{value.inspect}"
            result = binding[:block].call(value)
            puts "Binding block result for #{binding_path_str}: #{result.to_s}"

            # Garante que sempre teremos string
            inner_html =
              case result
              when Array
                result.map { |r| r.is_a?(Component) ? r.render_to_html : r.to_s }.join
              when Component
                result.render_to_html
              else
                result.to_s
              end
          rescue => e
            puts "⚠️ Erro ao renderizar binding #{binding_path_str}: #{e.class} - #{e.message}"
            inner_html = ""
          end

          puts "Generated inner_html for #{binding_path_str}: #{inner_html.inspect}"

          js = <<~JS
            (() => {
              const el = document.querySelector('[data-bind="#{binding_path_str}"]');
              if (el) el.innerHTML = #{inner_html.to_json};
            })();
          JS

          root = @parent_renderer
          while root && !root.is_a?(Frontend::RootRenderer)
            root = root.parent_renderer
          end

          if root && root.browser
           res = root.browser.execute(js)
          else
            warn "[WARN] notify_bindings: No valid browser context for #{self.class}"
          end

          puts "DOM updated for binding #{binding_path_str}"
        end
      end
      path_str
    end



    public
    def add_child(comp)
      comp.parent_renderer = self.parent_renderer
      puts "comp.inspect: #{comp.inspect}"
      @children << comp
    end

    def method_missing(method_name, *args, **kwargs, &block)
      tag(method_name, *args, **kwargs, &block)
    end

    def p(*args, **kwargs, &block)
      tag(:p, *args, **kwargs, &block)
    end

    def respond_to_missing?(method_name, include_private = false)
      true
    end

    def tag(name, *args, **attrs, &block)
      puts "tag called with name #{name}, args #{args.inspect}, attrs #{attrs.inspect}"
      content_or_attrs = args.first

      inner_content = if block
        result = instance_eval(&block)

        # Normaliza para array
        components = result.is_a?(Array) ? result : [result]

        # Adiciona cada filho e renderiza
        components.map do |c|
          add_child(c) if c.is_a?(Component)
          c.is_a?(Component) ? c.render_to_html : c.to_s
        end.join
      else
        content_or_attrs.is_a?(Component ) ? content_or_attrs.render_to_html : content_or_attrs.to_s
      end

      html_attrs = attrs.map do |k, v|
        if k.to_s.start_with?("on") && v.is_a?(Proc)
          puts "Adding event listener for #{k}"
          $root.bind_callback(k, v)
        else
          "#{k}=\"#{v}\""
        end
      end.join(" ")

      puts "html_attrs before event listeners: #{html_attrs}"

      @event_listeners.each do |event, proc_obj|
        html_attrs += " #{add_event_listener(event, &proc_obj)}"
      end

      @attrs.each do |k, v|
        html_attrs += " #{k}=\"#{v}\" "
      end

      res = "<#{name} #{html_attrs}>#{inner_content}</#{name}>"

      puts "Generated HTML for tag #{name}: #{res}"
      res
    end

    def render_to_html
      # Guard principal: verificar se o componente tem um bloco de renderização

      begin
        # Tentativa de renderização com segurança
        html = self.render
        unless html.is_a?(String)
          puts "⚠️ [GUARD] Resultado inesperado do render_block em #{self.class}: #{html.class}. Convertendo para string."
          html = html.to_s
        end

        puts "✅ [DEBUG] Renderização bem-sucedida em #{self.class}: tamanho #{html.length} chars"
        html

      rescue SyntaxError => e
        puts "💥 [ERROR] Erro de sintaxe ao renderizar #{self.class}: #{e.message}\n#{e.backtrace.first(3).join("\n")}"
        "<div class='error'>Erro de sintaxe em #{self.class}</div>"

      rescue NoMethodError => e
        puts "💥 [ERROR] Método não encontrado em #{self.class}: #{e.message}\n#{e.backtrace.first(3).join("\n")}"
        "<div class='error'>Método ausente: #{e.name}</div>"

      rescue StandardError => e
        puts "💥 [ERROR] Exceção geral ao renderizar #{self.class}: #{e.class} - #{e.message}"
        puts e.backtrace.first(5).join("\n")
        "<div class='error'>Erro interno em #{self.class}</div>"
      end
    end


    def run_js(js_code)
      @parent_renderer.browser.evaluate(js_code)
    end

    def rerender
      puts "called"
      @parent_renderer.render
    end
  end

  def +(other)
    self.render_to_html + (other.is_a?(Component) ? other.render_to_html : other.to_s)
  end
end

$display = Display.new
$shell = Shell.new($display)
$shell.setLayout(FillLayout.new)
$browser = Browser.new($shell, 0)
$root = Frontend::RootRenderer.new($browser)

at_exit do
  # Event loop
  while !$shell.disposed?
    $display.sleep unless $display.read_and_dispatch
  end
  $display.dispose  
end

module Agents
  class BrowserAutoAgent
    attr_reader :browser, :state, :display, :shell, :visible

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
    SERVER_PORT = "1235"

    puts "Importing model..."
    system("#{LMS_EXE_PATH} import #{MODEL_PATH} -y --hard-link")
    puts "Loading model..."
    system("#{LMS_EXE_PATH} load #{MODEL_IDENTIFIER} -y --identifier #{MODEL_IDENTIFIER}")
    puts "Starting LM Studio server... #{LMS_EXE_PATH}"
    spawn(LMS_EXE_PATH, "server", "start", "--port", SERVER_PORT, out: $stdout, err: $stderr)
    sleep 3 # aguarda servidor iniciar

    def initialize
      require 'ruby_llm'

      setup_llm

      # 🔁 Evita recriar se já houver loop ativo
      return if defined?($display_loop_started) && $display_loop_started

      Thread.new do
        @display = Display.new
        @shell = Shell.new(@display)
        @shell.setLayout(FillLayout.new)
        @browser = Browser.new(@shell, 0)
        @shell.setText("Agente de Automação")
        @visible = false
        @state = { current_url: nil, last_action: nil, context: {} }

        # ✅ Intercepta fechamento manual (fecha → só esconde)

        # 🚫 NÃO dá dispose do Display!
        while true
          begin
            @display.sleep unless @display.read_and_dispatch
          rescue Java::OrgEclipseSwt::SWTException => e
            puts "[Automation] ⚠️ Loop SWT interrompido: #{e.message}"
            break
          end
        end

        puts "[Automation] 🧩 Event loop encerrado (Display dispose manual)"
      end
    end

    # ===========================================================
    # Inicialização sob demanda
    # ===========================================================
    # ===========================================================
    # Navegação principal
    # ===========================================================

    def open(url, visible: true, on_changing: nil, on_changed: nil)
      run_async do

        @shell.setVisible(visible)
        @visible = visible

        browser = @browser

        if on_changing || on_changed
          listener = Class.new(LocationAdapter) do
            define_method(:changing) do |event|
              begin
                on_changing.call(event) if on_changing
              rescue => e
                puts "[open:on_changing] Erro: #{e.class} - #{e.message}"
              end
            end

            define_method(:changed) do |event|
              begin
                on_changed.call(event, browser) if on_changed
              rescue => e
                puts "[open:on_changed] Erro: #{e.class} - #{e.message}"
              end
            end
          end.new

          browser.addLocationListener(listener)
        end

        @browser.setUrl(url)
        @state[:current_url] = url
        @state[:last_action] = "open"
      end
    end
    def hide
      run_async { @shell.setVisible(false); @visible = false }
    end
    def reload
      run_async { @browser.refresh;  }
    end
    def back
      run_async { @browser.back; @state[:last_action] = "back" }
    end
    def forward
      run_async { @browser.forward; @state[:last_action] = "forward" }
    end
    # ===========================================================
    # Interações com a página
    # ===========================================================
    def click(selector)
      js = <<~JS
        (function() {
          var el = document.querySelector("#{selector}");
          if (el) el.click();
        })();
      JS
      run_async { @browser.execute(js) }
      @state[:last_action] = "click:#{selector}"
    end

    def type(selector, text)
      js = <<~JS
        (function() {
          var el = document.querySelector("#{selector}");
          if (el) {
            el.focus();
            el.value = "#{escape_js(text)}";
            el.dispatchEvent(new Event('input', { bubbles: true }));
          }
        })();
      JS
      run_async { @browser.execute(js) }
      @state[:last_action] = "type:#{selector}"
    end

    def submit(selector)
      js = <<~JS
        (function() {
          var el = document.querySelector("#{selector}");
          if (el && el.tagName === 'FORM') el.submit();
        })();
      JS
      run_async { @browser.execute(js) }
      @state[:last_action] = "submit:#{selector}"
    end

    # ===========================================================
    # Leitura e utilitários
    # ===========================================================
    def read_text(selector)
      evaluate(<<~JS, "read_text:#{selector}")
        (function() {
          var el = document.querySelector("#{selector}");
          return el ? el.innerText : null;
        })();
      JS
    end

    def read_html(selector)
      evaluate(<<~JS, "read_html:#{selector}")
        (function() {
          var el = document.querySelector("#{selector}");
          return el ? el.outerHTML : null;
        })();
      JS
    end

    def extract_links
      evaluate(<<~JS, "extract_links")
        Array.from(document.querySelectorAll('a'))
          .map(a => ({ text: a.innerText.trim(), href: a.href }));
      JS
    end

    def capture_dom
      evaluate("document.documentElement.outerHTML", "capture_dom")
    end

    def execute_script(js)
      run_async { @browser.execute(js) }
    end

    def evaluate_script(js)
      @browser.evaluate(js)
    end

    def escape_js(str)
      str.to_s.gsub('"', '\"').gsub("\n", "\\n")
    end
    # ===========================================================
    # Helpers internos
    # ===========================================================
    private

    def run_async(&block)
      # 🚀 Executa o bloco no display ativo
      begin
        @display.async_exec do
          begin
            block.call
          rescue => e
            puts "[run_async] ⚠️ Erro dentro do bloco: #{e.class} - #{e.message}"
          end
        end
      rescue Java::OrgEclipseSwt::SWTException => e
        puts "[run_async] 💥 SWTException: #{e.message}"
        # Se der erro mesmo assim, recria e tenta novamente
        retry
      end

    end


    module ApiAutomacoes
      def open_whatsapp(visible: true)
        open("https://web.whatsapp.com/", visible: visible)
      end

      def show
        run_async { @shell.setVisible(true); @visible = true }
      end

      def abrir(url)
        open(url, visible: true)
      end

      def rodar_teste(url)
        puts "rodando"

        open(
          url,
          visible: true,
          on_changing: ->(event) { puts "🔄 Navegando para #{event.location}" },
          on_changed:  ->(event, browser) { puts "✅ Página carregada: #{browser.evaluate('return document.title')}" }
        )
      end

      def send_whatsapp_message(contact_name, message)
        # ✅ 1. Garante que o ambiente gráfico existe
        if @display.nil? || @shell.nil? || @browser.nil? || @shell.disposed?
          puts "[Automation] ⚠️ Ambiente gráfico não disponível. Recriando..."
          open_whatsapp(visible: true)
          sleep 2
        end

        # ✅ 2. Garante que o WhatsApp Web está aberto
        current_url = nil
        begin
          current_url = @browser.getUrl
        rescue => e
          puts "[Automation] ⚠️ Erro ao obter URL: #{e.message}"
        end

        unless current_url&.include?("web.whatsapp.com")
          puts "[Automation] 🌐 WhatsApp Web não está aberto. Abrindo..."
          open_whatsapp(visible: true)
        end

        sleep 3

        # ✅ 5. Executa o JS para envio da mensagem
        js = <<~JS
          (function() {
            var chat = Array.from(document.querySelectorAll("span[title='#{escape_js(contact_name)}']")).pop();
            if (!chat) return "Contato não encontrado";
            chat.click();
            setTimeout(function() {
              var box = document.querySelector("div[contenteditable='true']");
              if (!box) return "Caixa de mensagem não encontrada";
              box.textContent = "#{escape_js(message)}";
              var evt = new InputEvent('input', { bubbles: true });
              box.dispatchEvent(evt);
              document.querySelector("span[data-icon='send']").click();
            }, 700);
            return "Mensagem enviada";
          })();
        JS

        result = evaluate(js, "whatsapp_send:#{contact_name}")
        puts "[Automation] Resultado do envio: #{result.inspect}"
        result
      end
      # ---- Portais de Licitação ----
      def open_licitacao(url = "https://www.gov.br/compras/pt-br/editais", visible: true)
        open(url, visible: visible)
      end

      def extract_editais
        js = <<~JS
          Array.from(document.querySelectorAll("table tr")).map(tr => {
            const cols = tr.querySelectorAll("td");
            return {
              nome: cols[0]?.innerText.trim(),
              orgao: cols[1]?.innerText.trim(),
              prazo: cols[2]?.innerText.trim()
            };
          });
        JS
        evaluate(js, "extract_editais")
      end

      def click_editais_com_prazo(dias)
        js = <<~JS
          (function() {
            let hoje = new Date();
            Array.from(document.querySelectorAll("table tr")).forEach(tr => {
              let prazo = tr.cells[2]?.innerText.trim();
              if (!prazo) return;
              let partes = prazo.split("/");
              if (partes.length === 3) {
                let data = new Date(partes[2], partes[1]-1, partes[0]);
                let diff = (data - hoje) / (1000*60*60*24);
                if (diff <= #{dias}) tr.click();
              }
            });
          })();
        JS
        run_async { @browser.execute(js) }
        @state[:last_action] = "click_editais_com_prazo<=#{dias}"
      end

    end

    include ApiAutomacoes

    public
    def setup_llm



      return @chat if defined?(@chat) && @chat

      RubyLLM.configure do |config|
        config.openai_api_key = 'none'
        config.openai_api_base = "http://127.0.0.1:#{SERVER_PORT}/v1"
      end

      @chat = RubyLLM.chat(
        model: MODEL_IDENTIFIER,
        provider: :openai,

        assume_model_exists: true
      )

      @chat.with_instructions <<~SYS
        Você é um agente de automação integrado ao módulo Ruby `Agents`.
        Seu papel é converter comandos em linguagem natural em chamadas Ruby diretas,
        usando os métodos disponíveis listados pelo sistema.

        ⚙️ Regras:
        - Retorne apenas **uma linha Ruby válida**, sem explicações.
        - Nunca invente métodos que não estão na lista.
        - Use parâmetros coerentes com os nomes e tipos indicados.
        - Prefira aspas duplas em strings.
        - Se não for possível mapear, retorne `nil`.

        Exemplo:
        Entrada: "mande mensagem para Maria dizendo oi"
        Saída: `Agents.whatsapp_enviar(contato: "Maria", mensagem: "oi")`
      SYS

      @chat.with_temperature(0.0)


      @chat
    end


    def funcoes_disponiveis
      # lista apenas os métodos definidos DIRETAMENTE no módulo
      api_methods = ApiAutomacoes.instance_methods(false)

      api_methods.map do |m|
        um = ApiAutomacoes.instance_method(m)
        # parameters: [[:keyreq, :contato], [:key, :visible], ...]
        args = um.parameters.map do |kind, name|
          # documenta como keyword (ex.: :contato, :visible)
          name
        end.compact
        { nome: m.to_s, args: args }
      end
    end

    # ===========================================================
    # 🧠 Interpreta e retorna uma linha Ruby direta
    # ===========================================================
    def interpretar(input_text)
      setup_llm

      lista_funcoes = funcoes_disponiveis.map do |f|
        args_sig = f[:args].map { |a| "#{a}:" }.join(", ")
        # instruímos o modelo a responder com Agents.<nome>(...)
        "Agents.#{f[:nome]}(#{args_sig})"
      end.join("\n")

      prompt = <<~PROMPT
        Comando do usuário:
        "#{input_text}"
    
        Métodos disponíveis (chame EXATAMENTE como abaixo):
        #{lista_funcoes}
    
        Gere apenas UMA linha Ruby chamando um dos métodos acima.
      PROMPT

      result = ""
      setup_llm.ask(prompt) { |chunk| result << chunk.content.to_s }

      # extrai a linha Agents.xxx(...)
      result.strip[/`?(Agents\..*?)`?$/m, 1]
    end

    # ===========================================================
    # 🚀 Executa o comando diretamente
    # ===========================================================
    def executar(input_text)
      code_line = interpretar(input_text)

      if code_line.nil? || code_line.strip.empty?
        puts "[Interpreter] ❌ Nenhum comando interpretado."
        return nil
      end

      puts "[Interpreter] Interpretação: #{code_line}"

      if code_line =~ /Agents\.(\w+)\s*\((.*)\)\s*$/
        metodo = Regexp.last_match(1)
        args_str = Regexp.last_match(2)
        args = parse_args(args_str) || {}

        unless ApiAutomacoes.instance_methods(false).map(&:to_s).include?(metodo)
          puts "[Interpreter] ⚠️ Método '#{metodo}' não faz parte da ApiAutomacoes."
          return nil
        end

        puts "[Interpreter] Chamando ApiAutomacoes##{metodo} com #{args.inspect}"

        begin
          method_ref = ApiAutomacoes.instance_method(metodo)
          params = method_ref.parameters
          puts "[Interpreter] Parâmetros esperados: #{params.inspect}"

          bound_method = method_ref.bind(self)

          if params.empty? || args.empty?
            puts "➡️ executando #{metodo} sem argumentos"
            result = bound_method.call
          elsif params.any? { |t, _| [:key, :keyreq, :keyrest].include?(t) }
            puts "➡️ executando #{metodo} com keyword args"
            result = bound_method.call(**args)
          else
            puts "➡️ executando #{metodo} com posicionais"
            result = bound_method.call(*args.values)
          end

          puts "[Interpreter] ✅ #{metodo} executado com sucesso."
          result

        rescue ArgumentError => e
          if e.message =~ /given 1, expected 0/
            puts "[Interpreter] ⚙️ Corrigindo execução para aceitar argumento fantasma..."
            begin
              result = ApiAutomacoes.instance_method(metodo).bind(self).call(nil)
              puts "[Interpreter] ✅ Reexecutado com argumento vazio."
              return result
            rescue => e2
              puts "[Interpreter] ❌ Falha final: #{e2.class} - #{e2.message}"
            end
          else
            puts "[Interpreter] ⚠️ ArgumentError: #{e.message}"
          end
          nil

        rescue => e
          puts "[Interpreter] 💥 Erro em '#{metodo}': #{e.class} - #{e.message}"
          puts e.backtrace.first(5).join("\n")
          nil
        end

      else
        puts "[Interpreter] ⚠️ Linha Ruby não reconhecida: #{code_line.inspect}"
        nil
      end
    end

    def parse_args(str)
      args = {}
      return args if str.nil? || str.strip.empty?

      # keywords com string: key: "value"
      str.scan(/(\w+):\s*"([^"]*)"/).each do |k, v|
        args[k.to_sym] = v
      end

      # keywords com numérico (ex.: dias: 7)
      str.scan(/(\w+):\s*(\d+)\b/).each do |k, v|
        args[k.to_sym] = v.to_i
      end

      args
    end

  end

end


