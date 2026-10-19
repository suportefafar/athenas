require "timeout"
require "tempfile"
require "socket"

module Lots
  class CommandRunner
    class Error < StandardError; end
    def call(*args, directory:, timeout: 120)
      sockets_before = office_sockets if File.basename(args.first.to_s) == "libreoffice"
      Tempfile.create("athenas-output", directory) do |output|
        pid = Process.spawn({ "HOME" => directory, "TMPDIR" => directory, "LANG" => "C.UTF-8", "PATH" => "/usr/local/bin:/usr/bin:/bin" },
          "python3", Rails.root.join("script/restricted_exec.py").to_s, *args.map(&:to_s),
          chdir: directory, pgroup: true, unsetenv_others: true, out: output, err: File::NULL)
        begin
          _, status = Timeout.timeout(timeout) { Process.wait2(pid) }
          raise Error, "Ferramenta #{File.basename(args.first.to_s)} falhou (código #{status.exitstatus || status.termsig})." unless status.success?
          raise Error, "Saída de extração excessiva." if output.size > 16.megabytes
          output.rewind
          output.read.force_encoding("UTF-8").scrub
        rescue Timeout::Error
          raise Error, "Tempo limite de extração excedido."
        ensure
          # Kill remaining converter descendants as well as a timed-out parent.
          begin
            Process.kill("KILL", -pid)
          rescue Errno::ESRCH
            nil
          end
          begin
            Process.wait(pid)
          rescue Errno::ECHILD
            nil
          end
        end
      end
    rescue Errno::ENOENT
      raise Error, "Ferramenta local de extração não instalada."
    ensure
      clean_office_sockets(sockets_before) if sockets_before
    end

    private

    def office_sockets
      Dir.glob("/tmp/OSL_PIPE_#{Process.uid}_SingleOfficeIPC_*")
    end

    def clean_office_sockets(before)
      (office_sockets - before).each do |path|
        stat = File.lstat(path)
        next unless stat.socket? && stat.uid == Process.uid
        socket = Socket.new(Socket::AF_UNIX, Socket::SOCK_STREAM, 0)
        begin
          socket.connect_nonblock(Socket.sockaddr_un(path))
        rescue Errno::ECONNREFUSED
          File.unlink(path) if File.lstat(path).ino == stat.ino
        rescue SystemCallError, IO::WaitWritable
          nil
        ensure
          socket.close
        end
      rescue SystemCallError
        nil
      end
    end
  end
end
