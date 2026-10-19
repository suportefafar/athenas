unless User.exists?(role: "admin")
  email = ENV["ADMIN_EMAIL"].presence
  password = ENV["ADMIN_PASSWORD"].presence
  abort "Primeira instalação: configure ADMIN_EMAIL e ADMIN_PASSWORD (mínimo de 12 caracteres)." unless email && password
  User.create!(name: "Administrador", email_address: email, password: password, role: "admin")
end
