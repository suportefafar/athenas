// Configure your import map in config/importmap.rb. Read more: https://github.com/rails/importmap-rails
import "@hotwired/turbo-rails"

document.addEventListener("turbo:load", () => {
  const history = document.querySelector("[data-chat-history]")
  if (!history) return

  const form = document.querySelector(".chat-form")
  const messages = history.querySelector("[data-chat-messages]")
  const input = form?.querySelector("textarea[name='content']")
  if (form && messages && input) {
    let pendingUser = null
    let pendingAnswer = null

    const scrollToLatest = () => { history.scrollTop = history.scrollHeight }
    const makeMessage = (role, content) => {
      const item = document.createElement("li")
      item.className = `chat-message ${role}`
      const meta = document.createElement("div")
      meta.className = "chat-message-meta"
      const label = document.createElement("p")
      label.className = "chat-message-label"
      label.textContent = role === "user" ? "Você" : "Athenas"
      meta.append(label)
      item.append(meta)
      const body = document.createElement("div")
      body.className = role === "user" ? "chat-bubble ffds-card" : "chat-thinking"
      body.textContent = content
      item.append(body)
      messages.append(item)
      return item
    }
    const showError = (item, message, prompt) => {
      item.removeAttribute("role")
      item.setAttribute("role", "alert")
      const body = item.querySelector(".chat-thinking")
      body.className = "chat-error ffds-card"
      body.textContent = ""
      const text = document.createElement("p")
      text.textContent = message
      const retry = document.createElement("button")
      retry.type = "button"
      retry.className = "ffds-btn ffds-btn-sm ffds-btn-outline-primary"
      retry.dataset.chatRetryPrompt = prompt
      retry.textContent = "Tentar novamente"
      body.append(text, retry)
      scrollToLatest()
    }

    form.addEventListener("turbo:submit-start", () => {
      const prompt = input.value.trim()
      if (!prompt) return
      history.querySelector(".chat-welcome")?.remove()
      pendingUser = makeMessage("user", prompt)
      pendingAnswer = makeMessage("assistant", "Pensando...")
      pendingAnswer.setAttribute("role", "status")
      input.value = ""
      scrollToLatest()
    })

    form.addEventListener("turbo:submit-end", (event) => {
      if (event.detail.success || !pendingAnswer) return
      const prompt = pendingUser?.querySelector(".chat-bubble")?.textContent || ""
      if (pendingUser) pendingUser.dataset.chatFailed = ""
      showError(pendingAnswer, "Não foi possível enviar a pergunta. Tente novamente.", prompt)
      pendingAnswer = null
    })

    messages.addEventListener("click", (event) => {
      const retry = event.target.closest("[data-chat-retry-prompt]")
      if (!retry || form.querySelector("input[type='submit']:disabled")) return
      input.value = retry.dataset.chatRetryPrompt
      const error = retry.closest(".chat-message")
      if (error?.previousElementSibling?.matches("[data-chat-failed]")) error.previousElementSibling.remove()
      error?.remove()
      form.requestSubmit()
    })
  }

  requestAnimationFrame(() => {
    history.scrollTop = history.scrollHeight
  })
})
