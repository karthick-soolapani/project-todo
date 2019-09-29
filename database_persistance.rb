require 'pg'

class DatabasePersistance

  def initialize(logger)
    @db = if Sinatra::Base.production?
            PG.connect(ENV['DATABASE_URL'])
          else
            PG.connect(dbname: 'todos')
          end

    @logger = logger
  end

  def disconnect
    @db.close
  end

  def query(statement, *params)
    loc = caller_locations(1,1).first
    @logger.info("#{loc.path.split('/').last}:#{loc.lineno} in #{loc.label}")
    @logger.info("SQL STATEMENT: #{statement} | PARAMS: #{params}")

    @db.exec_params(statement, params)
  end

  def all_lists
    sql = <<~SQL
      SELECT lists.*,
             COUNT(todos.id) AS todos_count,
             COUNT(NULLIF(completed, true)) AS todos_remaining_count
        FROM lists
          LEFT JOIN todos ON (lists.id = todos.list_id)
          GROUP BY lists.id
          ORDER BY lists.id
    SQL

    result = query(sql)

    format_lists(result)
  end

  def fetch_list(list_id)
    sql = <<~SQL
      SELECT lists.*,
             COUNT(todos.id) AS todos_count,
             COUNT(NULLIF(completed, true)) AS todos_remaining_count
        FROM lists
          LEFT JOIN todos ON (lists.id = todos.list_id)
          WHERE lists.id = $1
          GROUP BY lists.id
          ORDER BY lists.id
    SQL

    result = query(sql, list_id)

    format_lists(result).first
  end

  def all_todos_for_list(list_id)
    sql = "SELECT * FROM todos WHERE list_id = $1"
    result = query(sql, list_id)

    format_todos(result)
  end

  def fetch_todo(list_id, todo_id)
    sql = "SELECT * FROM todos WHERE id = $1 AND list_id = $2"
    result = query(sql, todo_id, list_id)

    format_todos(result).first
  end

  def create_new_list(list_name)
    sql = "INSERT INTO lists (name) VALUES ($1)"
    query(sql, list_name)
  end

  def update_list_name(list_id, new_name)
    sql = "UPDATE lists SET name = $2 WHERE id = $1"
    query(sql, list_id, new_name)
  end

  def delete_list(list_id)
    sql = "DELETE FROM lists WHERE id = $1"
    query(sql, list_id)
  end

  def create_new_todo(list_id, todo_name)
    sql = "INSERT INTO todos (list_id, name) VALUES ($1, $2)"
    query(sql, list_id, todo_name)
  end

  def delete_todo(list_id, todo_id)
    sql = "DELETE FROM todos WHERE id = $1 AND list_id = $2"
    query(sql, todo_id, list_id)
  end

  def update_todo_status(list_id, todo_id, new_status)
    sql = "UPDATE todos SET completed = $1 WHERE id = $2 AND list_id = $3"
    query(sql, new_status, todo_id, list_id)
  end

  def mark_all_todos_for_list_as_completed(list_id)
    sql = "UPDATE todos SET completed = true WHERE list_id = $1"
    query(sql, list_id)
  end

  private

  def format_lists(lists)
    lists.map do |tuple|
      {
        id: tuple['id'].to_i,
        name: tuple['name'],
        todos_count: tuple['todos_count'].to_i,
        todos_remaining_count: tuple['todos_remaining_count'].to_i
      }
    end
  end

  def format_todos(todos)
    todos.map do |tuple|
      {
        id: tuple['id'].to_i,
        name: tuple['name'],
        completed: tuple['completed'] == 't'
      }
    end
  end

end