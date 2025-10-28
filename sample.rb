require_relative 'glauco-framework'

include Frontend
include Agents

class BrowserDemo < Component
  def initialize(parent_renderer:)
    super(parent_renderer: parent_renderer)
    @state[:conteudo] = "Aguardando..."
    @automation = WebAutomation.new
  end

  def render
    div(style: "padding: 20px; background-color: #222; color: white; font-family: sans-serif;") do

      h2 { "Demo: WebAutomation" } +

        bind(:conteudo, div(style: "margin-bottom: 15px;")) { |conteudo|
          "📜 Status: #{conteudo}"
        } +

        # ====== Linha 1: Controle geral ======
        div(style: "margin-bottom: 10px;") do
          button(onclick: proc {
            @automation.open("https://www.google.com")
            @state[:conteudo] = "Abriu Google"
          }) { "🌐 Abrir Google" } +

            button(onclick: proc {
              @automation.reload
              @state[:conteudo] = "Recarregou página"
            }, style: "margin-left: 10px;") { "🔁 Recarregar" } +

            button(onclick: proc {
              @automation.back
              @state[:conteudo] = "Voltou"
            }, style: "margin-left: 10px;") { "⬅️ Voltar" } +

            button(onclick: proc {
              @automation.forward
              @state[:conteudo] = "Avançou"
            }, style: "margin-left: 10px;") { "➡️ Avançar" }
        end +

        # ====== Linha 2: Controle de janela ======
        div(style: "margin-bottom: 10px;") do
          button(onclick: proc {
            @automation.show
            @state[:conteudo] = "Janela visível"
          }) { "👁️ Mostrar janela" } +

            button(onclick: proc {
              @automation.hide
              @state[:conteudo] = "Janela oculta (rodando em background)"
            }, style: "margin-left: 10px;") { "🙈 Ocultar janela" }
        end +

        # ====== Linha 3: Interações com página ======
        div(style: "margin-bottom: 10px;") do
          button(onclick: proc {
            @automation.type("input[name='q']", "Glauco Framework Ruby")
            @state[:conteudo] = "Digitou no campo de busca"
          }) { "⌨️ Digitar texto" } +

            button(onclick: proc {
              @automation.submit("form")
              @state[:conteudo] = "Submeteu formulário"
            }, style: "margin-left: 10px;") { "📤 Submeter" } +

            button(onclick: proc {
              @automation.click("input[type='submit']")
              @state[:conteudo] = "Clicou botão"
            }, style: "margin-left: 10px;") { "🖱️ Clicar botão" }
        end +

        # ====== Linha 4: Leitura de conteúdo ======
        div(style: "margin-bottom: 10px;") do
          button(onclick: proc {
            texto = @automation.read_text("body")
            @state[:conteudo] = "Texto lido: #{texto[0..80]}..."
          }) { "📖 Ler texto" } +

            button(onclick: proc {
              html = @automation.read_html("body")
              @state[:conteudo] = "HTML capturado (#{html.size} chars)"
            }, style: "margin-left: 10px;") { "🧾 Ler HTML" } +

            button(onclick: proc {
              links = @automation.extract_links
              if links && links.any?
                @state[:conteudo] = "Encontrados #{links.size} links (ex: #{links.first[:href]})"
              else
                @state[:conteudo] = "Nenhum link encontrado"
              end
            }, style: "margin-left: 10px;") { "🔗 Extrair links" }
        end +

        # ====== Linha 5: Execução de scripts ======
        div(style: "margin-bottom: 10px;") do
          button(onclick: proc {
            @automation.execute_script("document.body.style.background='lightyellow'")
            @state[:conteudo] = "Executou JS: mudou cor do fundo"
          }) { "🎨 Executar script" } +

            button(onclick: proc {
              title = @automation.evaluate_script("document.title")
              @state[:conteudo] = "Título da página: #{title}"
            }, style: "margin-left: 10px;") { "📋 Avaliar script" }
        end +

        # ====== Linha 6: WhatsApp (exemplo especializado) ======
        div(style: "margin-bottom: 10px;") do
          button(onclick: proc {
            @automation.open_whatsapp
            @state[:conteudo] = "Abriu WhatsApp Web"
          }) { "💬 Abrir WhatsApp Web" } +

            button(onclick: proc {
              resultado = @automation.send_whatsapp_message("Contato Teste", "Olá via automação Ruby!")
              @state[:conteudo] = "WhatsApp: #{resultado}"
            }, style: "margin-left: 10px;") { "📨 Enviar mensagem" }
        end +

        # ====== Linha 7: Licitações (exemplo especializado) ======
        div(style: "margin-bottom: 10px;") do
          button(onclick: proc {
            @automation.open_licitacao("https://www.gov.br/compras/pt-br/editais")
            @state[:conteudo] = "Abriu portal de licitações"
          }) { "🏛️ Abrir portal de licitações" } +

            button(onclick: proc {
              editais = @automation.extract_editais
              @state[:conteudo] = "Extraídos #{editais&.size || 0} editais"
            }, style: "margin-left: 10px;") { "📑 Extrair editais" } +

            button(onclick: proc {
              @automation.click_editais_com_prazo(7)
              @state[:conteudo] = "Clicou editais com prazo ≤ 7 dias"
            }, style: "margin-left: 10px;") { "⏰ Editais com prazo curto" }
        end
    end
  end
end

class AgentsChatDemo < Component

  def initialize(parent_renderer:)
    super(parent_renderer: parent_renderer)
    @automation = BrowserAutoAgent.new
    @state = {
      messages: [
        { sender: :agent, text: "👋 Olá! Sou o agente de automação. Envie um comando, por exemplo:\n  - 'Abrir o WhatsApp'\n  - 'Mandar mensagem para João dizendo oi'\n  - 'Abrir o site da prefeitura'" }
      ],
      status: "Aguardando comando...",
      input: ""
    }
  end

  def render
    div(style: "background:#1e1e1e; color:white; font-family:sans-serif; height:100%; display:flex; flex-direction:column;") do

      # Título
      h2(style: "padding:10px; background:#333; margin:0;") { "💬 Agente Interativo (LLM + Browser)" } +

        # Histórico de mensagens
        bind(:messages, div(id: "chat-box", style: "flex:1; overflow-y:auto; padding:10px;")) do |messages|
          messages.map do |msg|
            align = msg[:sender] == :user ? "flex-end" : "flex-start"
            bg = msg[:sender] == :user ? "#007acc" : "#444"
            div(style: "display:flex; justify-content:#{align}; margin:5px 0;") do
              div(style: "max-width:75%; background:#{bg}; padding:10px; border-radius:10px; white-space:pre-wrap;") { msg[:text] }
            end
          end.reduce(:+)
        end +

        # Caixa de entrada
        div(style: "padding:10px; background:#2b2b2b; display:flex;") do
          input(
            type: "text",
            id: "chat-input",
            placeholder: "Digite um comando (ex: 'abrir o WhatsApp')",
            oninput: proc { |e|
              set_state(:input, e)
            },
            style: "flex:1; padding:10px; border-radius:6px; border:none; color:black;"
          ) +

            button(onclick: proc {
              comando = @state[:input][0]
              next if comando.strip.empty?

              # Adiciona mensagem do usuário
              set_state(:messages, @state[:messages] + [{ sender: :user, text: comando }])
              set_state(:status, "Interpretando comando...")

              # Processamento assíncrono via automação
              @automation.send(:run_async) do
                @automation.executar(comando)
              end
            },
                   style: "margin-left:10px; background:#007acc; color:white; border:none; border-radius:6px; padding:10px 15px; cursor:pointer;"
            ) { "Enviar" }
        end +

        # Status
        bind(:status, div(style: "background:#111; padding:5px 10px; color:#aaa; font-size:0.9em;")) do |s|
          "🔍 #{s}"
        end
    end
  end

  # ===========================================================
  # Métodos auxiliares
  # ===========================================================
  def append_agent_message(text)
    @messages << { sender: :agent, text: text }
    update_view
  end

  def update_view
    set_state(:refresh, rand) # força re-renderização
  end
end


# ====== App Rendering ======
app = AgentsChatDemo.new(parent_renderer: $root)
$root.root_component = app
$root.render

$shell.setSize(900, 700)
$shell.open
