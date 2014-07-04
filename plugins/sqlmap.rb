require 'sqlmap/sqlmap_session'
require 'sqlmap/sqlmap_manager'
require 'json'

module Msf
  class Plugin::Sqlmap < Msf::Plugin
    class SqlmapCommandDispatcher
      include Msf::Ui::Console::CommandDispatcher

      def name
        "Sqlmap"
      end

      def commands
        {
          "sqlmap_new_task" => "It's a task!",
          "sqlmap_connect" => "sqlmap_connect <host> [<port>]",
          "sqlmap_list_tasks" => "List the knows tasks. Not stored in a DB, so lives as long as the console does",
          "sqlmap_get_option" => "Get an option for a task",
          "sqlmap_set_option" => "Set an option for a task",
          "sqlmap_start_task" => "Start the task",
          "sqlmap_get_status" => "Get the status of a task",
          "sqlmap_get_log" => "Get the running log of a task",
          "sqlmap_get_data" => "Get the resulting data of the task",
          "sqlmap_save_data" => "Save the resulting data as web_vulns"
        }
      end

      def cmd_sqlmap_connect(*args)
        if args.length == 0
          print_error("Need a host, and optionally a port")
          return
        end

        host = args[0]
        port = args.length == 2 ? args[1] : nil

        if !port
          @manager = Sqlmap::Manager.new(Sqlmap::Session.new(host))
        else
          @manager = Sqlmap::Manager.new(Sqlmap::Session.new(host, port))
        end

        print_good("Set connection settings for host " + host + (port ? " on port " + port : ""))
      end

      def cmd_sqlmap_set_option(*args)
        if args.length != 3
          print_error("Usage:")
          print_error("\tsqlmap_set_option <taskid> <option_name> <option_value>")
          return
        end

        if !@manager
          print_error("Please run sqlmap_connect <host> first.")
          return
        end

        val = args[2]
        if args[2] =~ /^\d+$/
          val = val.to_i
        end

        res = @manager.set_option(args[0], args[1], val)
        print_status("Success: " + res["success"].to_s)
      end

      def cmd_sqlmap_start_task(*args)
        if args.length == 0
          print_error("Usage:")
          print_error("\tsqlmap_start_task <taskid> [<url>]")
          return
        end

        options = {}

        if args.length == 2
          options['url'] = args[1]
        end

        if !options['url'] && @tasks[args[0]]['url'] == ''
          print_error("You need to specify a URL either as an argument to sqlmap_start_task or sqlmap_set_option")
          return
        end

        if !@manager
          print_error("Please run sqlmap_connect <host> first.")
          return
        end

        res = @manager.start_task(args[0], options)
        print_status("Started task: " + res["success"].to_s)
      end

      def cmd_sqlmap_get_log(*args)
        if args.length != 1
          print_error("Usage:")
          print_error("\tsqlmap_get_log <taskid>")
          return
        end

        if !@manager
          print_error("Please run sqlmap_connect <host> first.")
          return
        end

        res = @manager.get_task_log(args[0])

        res["log"].each do |message|
          print_status("[#{message["time"]}] #{message["level"]}: #{message["message"]}")
        end
      end

      def cmd_sqlmap_get_status(*args)
        if args.length != 1
          print_error("Usage:")
          print_error("\tsqlmap_get_status <taskid>")
          return
        end

        if !@manager
          print_error("Please run sqlmap_connect <host> first.")
          return
        end

        res = @manager.get_task_status(args[0])

        print_status("Status: " + res['status'])

      end

      def cmd_sqlmap_get_data(*args)
        if args.length != 1
          print_error("Usage:")
          print_error("\tsqlmap_get_data <taskid>")
          return
        end

        @tasks = {} if !@tasks

        if !@manager
          print_error("Please run sqlmap_connect <host> first.")
          return
        end

        @tasks[args[0]] = @manager.get_options(args[0])["options"]

        print_line
        print_status("URL: " + @tasks[args[0]]['url'])

        res = @manager.get_task_data(args[0])

        tbl = Rex::Ui::Text::Table.new(
          'Columns' => ['Title','Payload'])

        res["data"].each do |d|
          d["value"].each do |v|
            v["data"].each do |i|
              title = i[1]["title"].split('-')[0]
              payload = i[1]["payload"]
              tbl << [title, payload]
            end
          end
        end

        print_line
        print_line tbl.to_s
        print_line
      end

      def cmd_sqlmap_save_data(*args)
        if args.length != 1
          print_error("Usage:")
          print_error("\tsqlmap_save_data <taskid>")
          return
        end

        if !(framework.db && framework.db.usable)
          print_error("No database is connected or usable")
          return
        end

        @tasks = {} if !@tasks

        if !@manager
          print_error("Please run sqlmap_connect <host> first.")
          return
        end

        @tasks[args[0]] = @manager.get_options(args[0])["options"]

        print_line
        print_status("URL: " + @tasks[args[0]]['url'])

        res = @manager.get_task_data(args[0])
        web_vuln_info = {}
        url = @tasks[args[0]]['url']
        proto = url.split(":")[0]
        host = url.split("/")[2]
        port = 80
        port = host.split(":")[1] if host.index(":")
        host = host.split(":")[0] if host.index(":")
        path = '/' + (url.split("/")[3..(url.split("/").length - 1)].join('/'))
        query = url.split("?")[1]
        web_vuln_info[:web_site] = url
        web_vuln_info[:path] = path
        web_vuln_info[:query] = query
        web_vuln_info[:host] = host
        web_vuln_info[:port] = port
        web_vuln_info[:ssl] = (proto =~ /https/)
        web_vuln_info[:category] = "imported from sqlmap"
        res["data"].each do |d|
          d["value"].each do |v|
            web_vuln_info[:pname] = v["parameter"]
            web_vuln_info[:method] = v["place"]
            web_vuln_info[:payload] = v["suffix"]
            v["data"].each do |k,i|
              web_vuln_info[:name] = i["title"]
              web_vuln_info[:description] = res.to_json
              web_vuln_info[:proof] = i["payload"]
              framework.db.report_web_vuln(web_vuln_info)
            end
          end
        end
        print_good("Saved vulnerabilities to database.")    
      end

      def cmd_sqlmap_get_option(*args)
        @tasks = {} if !@tasks
        if args.length != 2
          print_error("Usage:")
          print_error("\tsqlmap_get_option <taskid> <option_name>")
        end

        if !@manager
          print_error("Please run sqlmap_connect <host> first.")
          return
        end

        task_options = @manager.get_options(args[0])
        @tasks[args[0]] = task_options["options"]
        print_good(args[1] + ": " + @tasks[args[0]][args[1]].to_s)
      end

      def cmd_sqlmap_new_task(*args)
        @tasks = {} if !@tasks

        if !@manager
          print_error("Please run sqlmap_connect <host> first.")
          return
        end

        taskid = @manager.new_task['taskid']
        task_options = @manager.get_options(taskid)
        @tasks[taskid] = task_options["options"]
        print_good("Created task: " + taskid)
      end

      def cmd_sqlmap_list_tasks(*args)
        @tasks = {} if !@tasks
        @tasks.each do |task, options|
          print_good("Task ID: " + task)
        end
      end
    end

    def initialize(framework, opts)
      super

      add_console_dispatcher(SqlmapCommandDispatcher)

      print_status("Sqlmap plugin loaded")
    end

    def cleanup
      remove_console_dispatcher('Sqlmap')
    end

    def name
      "Sqlmap"
    end

    def desc
      "Use Sqlmap, yo!"
    end
  end
end
