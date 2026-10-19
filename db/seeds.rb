email = ENV["ADMIN_EMAIL"].presence
admin = User.find_by(role: "admin")

if admin
  admin.update!(email_address: email) if Rails.env.production? && email && admin.email_address != email.strip.downcase
else
  password = ENV["ADMIN_PASSWORD"].presence
  abort "Primeira instalação: configure ADMIN_EMAIL e ADMIN_PASSWORD (mínimo de 12 caracteres)." unless email && password
  User.create!(name: "Administrador", email_address: email, password: password, role: "admin")
end
