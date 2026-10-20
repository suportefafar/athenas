// Configure your import map in config/importmap.rb. Read more: https://github.com/rails/importmap-rails
import "@hotwired/turbo-rails"

document.addEventListener("turbo:load", () => {
  const history = document.querySelector("[data-chat-history]")
  if (!history) return

  requestAnimationFrame(() => {
    history.scrollTop = history.scrollHeight
  })
})
