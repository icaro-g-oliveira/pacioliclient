
module ApiAutomacoes
  def open_whatsapp(visible: true)
    open_url("https://web.whatsapp.com/", visible: visible)
  end

  def open_url(url:, visible: true, on_changing: nil, on_changed: nil)
    # Abaixo, action causador do efeito colateral de abrir a URL no browser
      run_async do
        @shell.setVisible(visible)
        @visible = visible

        browser = @browser

        if on_changing || on_changed
          listener = Class.new(LocationAdapter) do
            define_method(:changing) do |event|
              on_changing&.call(event)
            rescue => e
              puts "[open:on_changing] Erro: #{e.class} - #{e.message}"
            end

            define_method(:changed) do |event|
              on_changed&.call(event, browser)
            rescue => e
              puts "[open:on_changed] Erro: #{e.class} - #{e.message}"
            end
          end.new

          browser.addLocationListener(listener)
        end

        @browser.setUrl(url)
        @state[:current_url] = url
        @state[:last_action] = "open"
        
      end
  end

  alias_method :navigate, :open
  alias_method :abrir_site, :open
  alias_method :abrir, :open
  
  def ler_conteudo_página_no_elemento(seletor)
    result = ""
    setup_llm.ask(" 
      Acesse a página atual e extraia o conteúdo do elemento identificado pelo seletor CSS \"#{seletor}\".
      Código html da página é o seguinte:
      #{ read_html('body') }  
    ") { |chunk| result << chunk.content.to_s }
    result    
  end

  def rodar_teste(url)
    puts "rodando"

    open_url(
      url,
      visible: true,
      on_changing: ->(event) { puts "🔄 Navegando para #{event.location}" },
      on_changed:  ->(event, browser) { puts "✅ Página carregada: #{browser.evaluate('return document.title')}" }
    )
  end

  # 
end