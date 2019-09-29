require "sinatra"
require "sinatra/content_for"
require "tilt/erubis"

require_relative "database_persistance"

configure (:development) do
  require "sinatra/reloader"
  also_reload 'database_persistance.rb'
end

configure do
  enable :sessions
  set :session_secret, 'secret'

  set :erb, :escape_html => true
end

helpers do
  def list_complete?(list)
    list[:todos_count] > 0 && list[:todos_remaining_count] == 0
  end

  def list_class(list)
    if list_complete?(list)
      "complete"
    elsif list[:todos_count] == 0
      "empty"
    end
  end

  def todo_class(todo)
    "complete" if todo[:completed]
  end

  def sort_lists(lists, &block)
    completed_lists, not_completed_lists = lists.partition { |list| list_complete?(list) }

    not_completed_lists.each(&block)
    completed_lists.each(&block)
  end

  def sort_todos(todos, &block)
    completed_todos, not_completed_todos = todos.partition { |todo| todo[:completed] }

    not_completed_todos.each(&block)
    completed_todos.each(&block)
  end
end

def error_for_list(list_name)
  if !(1..100).cover?(list_name.size)
    "List name must be between 1 and 100 characters."
  elsif @storage.all_lists.any? { |list| list[:name].casecmp? list_name }
    "List name must be unique."
  end
end

def error_for_todo(todo_name, todos)
  if !(1..100).cover?(todo_name.size)
    "Todo must be between 1 and 100 characters."
  elsif todos.any? { |todo| todo[:name].casecmp? todo_name }
    "Todo must be unique."
  end
end

def load_list(list_id)
  list = @storage.fetch_list(list_id)

  return list if list

  session[:error] = "The specified list was not found."
  redirect "/lists"
end

def load_todo(list_id, todo_id)
  todo = @storage.fetch_todo(list_id, todo_id)

  return todo if todo

  session[:error] = "The specified todo was not found."
  redirect "/lists/#{list_id}"
end

before do
  @storage = DatabasePersistance.new(logger)
end

after do
  @storage.disconnect
end

get "/" do
  redirect "/lists"
end

# View all lists
get "/lists" do
  @lists = @storage.all_lists

  erb :lists
end

# View new list form
get "/lists/new" do
  erb :new_list
end

# Create a new list
post "/lists" do
  list_name = params[:list_name].strip
  error = error_for_list(list_name)

  if error
    session[:error] = error
    erb :new_list
  else
    @storage.create_new_list(list_name)
    session[:success] = "The list has been created."
    redirect "/lists"
  end
end

# View a single list
get "/lists/:list_id" do
  @list_id = params[:list_id].to_i
  @list = load_list(@list_id)
  @todos = @storage.all_todos_for_list(@list_id)

  erb :list
end

# View the edit list form
get "/lists/:list_id/edit" do
  @list_id = params[:list_id].to_i
  @list = load_list(@list_id)

  erb :edit_list
end

# Update a list
post "/lists/:list_id" do
  @list_id = params[:list_id].to_i
  @list = load_list(@list_id)

  list_name = params[:list_name].strip
  error = error_for_list(list_name) unless @list[:name].casecmp? list_name

  if error
    session[:error] = error
    erb :edit_list
  else
    @storage.update_list_name(@list_id, list_name)
    session[:success] = "The list has been updated."
    redirect "/lists/#{@list_id}"
  end
end

# Delete a list
post "/lists/:list_id/delete" do
  @list_id = params[:list_id].to_i
  @list = load_list(@list_id)

  @storage.delete_list(@list_id)

  return "/lists" if env["HTTP_X_REQUESTED_WITH"] == "XMLHttpRequest"

  session[:success] = "The list has been deleted."
  redirect "/lists"
end

# Add a new todo to a list
post "/lists/:list_id/todos" do
  @list_id = params[:list_id].to_i
  @list = load_list(@list_id)
  @todos = @storage.all_todos_for_list(@list_id)

  todo_name = params[:todo].strip
  error = error_for_todo(todo_name, @todos)

  if error
    session[:error] = error
    erb :list
  else
    @storage.create_new_todo(@list_id, todo_name)
    session[:success] = "The todo was added."
    redirect "/lists/#{@list_id}"
  end
end

# Delete a todo from a list
post "/lists/:list_id/todos/:todo_id/delete" do
  @list_id = params[:list_id].to_i
  @list = load_list(@list_id)

  @todo_id = params[:todo_id].to_i
  @todo = load_todo(@list_id, @todo_id)

  @storage.delete_todo(@list_id, @todo_id)

  return status(204) if env["HTTP_X_REQUESTED_WITH"] == "XMLHttpRequest"

  session[:success] = "The todo has been deleted."
  redirect "/lists/#{@list_id}"
end

# Update todo status
post "/lists/:list_id/todos/:todo_id" do
  @list_id = params[:list_id].to_i
  @list = load_list(@list_id)

  @todo_id = params[:todo_id].to_i
  @todo = load_todo(@list_id, @todo_id)

  completed = params[:completed]

  case completed
  when "true"
    @storage.update_todo_status(@list_id, @todo_id, true)
    session[:success] = "Todo completed."
  when "false"
    @storage.update_todo_status(@list_id, @todo_id, false)
    session[:success] = "Todo completion reverted."
  end

  redirect "/lists/#{@list_id}"
end

# Mark all todos in a list as completed
post "/lists/:list_id/all_completed" do
  @list_id = params[:list_id].to_i
  @list = load_list(@list_id)

  @storage.mark_all_todos_for_list_as_completed(@list_id)
  session[:success] = "All Todos completed."

  redirect "/lists/#{@list_id}"
end

not_found do
  erb "<h2>Page not found</h2>", layout: :layout
end
