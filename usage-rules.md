# Bonfire.Epics Usage Rules

Bonfire.Epics is a workflow orchestration framework that enables composable, multi-step operations with error handling and parallel execution. These rules ensure effective usage of this powerful pattern.

## Core Concepts

### Epic

An Epic represents a complete workflow with sequential or parallel Acts:

```elixir
%Bonfire.Epics.Epic{
  acts: [Act1, {Act2, opts}, [Act3, Act4]],  # Sequential and parallel
  assigns: %{current_user: user, data: data}, # Shared state
  errors: []                                   # Accumulated errors
}
```

### Act

An Act is a single operation within an Epic:

```elixir
defmodule MyApp.Acts.ProcessDataAct do
  use Bonfire.Epics.Act
  
  @impl true
  def run(epic, act) do
    # Process data and update epic.assigns
    updated_assigns = Map.put(epic.assigns, :result, "processed")
    {:ok, %{epic | assigns: updated_assigns}}
  end
end
```

## Writing Acts

### Basic Act Structure

```elixir
defmodule MyApp.Acts.CreatePostAct do
  use Bonfire.Epics.Act
  alias Bonfire.Epics.Epic
  
  @doc """
  Creates a post from epic.assigns.attrs
  """
  @impl true
  def run(%Epic{assigns: %{attrs: attrs, current_user: user}} = epic, _act) do
    case Posts.create(user, attrs) do
      {:ok, post} ->
        {:ok, Epic.assign(epic, :post, post)}
        
      {:error, changeset} ->
        {:error, Epic.add_error(epic, act: :create_post, changeset: changeset)}
    end
  end
  
  # Handle missing required data
  def run(epic, _act) do
    {:error, Epic.add_error(epic, act: :create_post, message: "Missing attrs or user")}
  end
end
```

### Act Options

Acts can receive configuration options:

```elixir
defmodule MyApp.Acts.NotifyAct do
  use Bonfire.Epics.Act
  
  @impl true
  def run(epic, act) do
    # Access act options
    channels = act.options[:channels] || [:email, :push]
    urgent = act.options[:urgent] || false
    
    # Use options in logic
    if urgent do
      send_immediate_notifications(epic.assigns.user, channels)
    else
      queue_notifications(epic.assigns.user, channels)
    end
    
    {:ok, epic}
  end
end

# Usage in epic definition
acts: [
  {MyApp.Acts.NotifyAct, channels: [:email], urgent: true}
]
```

### Error Handling in Acts

Always handle errors gracefully:

```elixir
defmodule MyApp.Acts.ExternalAPIAct do
  use Bonfire.Epics.Act
  import Bonfire.Epics.Epic
  
  @impl true
  def run(epic, act) do
    case external_api_call(epic.assigns.data) do
      {:ok, response} ->
        {:ok, assign(epic, :api_response, response)}
        
      {:error, %{status: 429}} ->
        # Rate limited - could be retried
        {:error, add_error(epic, 
          act: :external_api,
          error: :rate_limited,
          retry_after: 60
        )}
        
      {:error, reason} ->
        # Other errors
        {:error, add_error(epic, 
          act: :external_api,
          error: reason
        )}
    end
  end
end
```

## Defining Epics

### Sequential Execution

Acts run one after another:

```elixir
# In config or module
epic = %Bonfire.Epics.Epic{
  acts: [
    MyApp.Acts.ValidateAct,
    MyApp.Acts.CreateAct,
    MyApp.Acts.IndexAct,
    MyApp.Acts.NotifyAct
  ]
}

# Run the epic
result = Bonfire.Epics.run(epic, %{
  current_user: user,
  attrs: %{title: "Hello", body: "World"}
})
```

### Parallel Execution

Acts in nested lists run concurrently:

```elixir
epic = %Bonfire.Epics.Epic{
  acts: [
    MyApp.Acts.ValidateAct,        # Runs first
    [                              # These run in parallel
      MyApp.Acts.IndexSearchAct,
      MyApp.Acts.GenerateThumbnailAct,
      MyApp.Acts.ExtractMetadataAct
    ],
    MyApp.Acts.NotifyAct           # Runs after parallel acts complete
  ]
}
```

### Configuration-Based Epics

Define epics in config:

```elixir
# In config.exs
config :my_app, :epics,
  create_post: [
    {Bonfire.Social.Acts.PostContentsAct, []},
    {Bonfire.Social.Acts.ThreadedAct, []},
    {Bonfire.Social.Acts.FederateAct, []}
  ],
  update_profile: [
    MyApp.Acts.ValidateProfileAct,
    MyApp.Acts.UpdateProfileAct,
    {MyApp.Acts.NotifyFollowersAct, delay: 30}
  ]

# Usage
epic = Bonfire.Epics.from_config!(:create_post)
Bonfire.Epics.run(epic, assigns)
```

## Running Epics

### Basic Execution

```elixir
# Create and run
epic = %Bonfire.Epics.Epic{acts: acts}
{:ok, result_epic} = Bonfire.Epics.run(epic, %{
  current_user: user,
  attrs: attrs
})

# Access results
created_object = result_epic.assigns[:object]
```

### With Error Handling

```elixir
case Bonfire.Epics.run(epic, assigns) do
  {:ok, epic} ->
    # Success - all acts completed
    {:ok, epic.assigns.result}
    
  {:error, epic} ->
    # One or more acts failed
    handle_errors(epic.errors)
end
```

### Running Specific Acts

```elixir
# Run a single act directly
act = %Bonfire.Epics.Act{module: MyAct, options: []}
epic = %Bonfire.Epics.Epic{assigns: %{data: data}}

{:ok, updated_epic} = Bonfire.Epics.Acts.run(epic, act)
```

## Database Transactions

Use epic database transactions for data consistency:

```elixir
defmodule MyApp.Acts.DatabaseAct do
  use Bonfire.Epics.Act
  use Bonfire.Ecto.ActRepo
  
  @impl true
  def run(epic, act) do
    # Automatically runs in the epic's transaction
    case repo().insert(changeset) do
      {:ok, record} ->
        {:ok, Epic.assign(epic, :record, record)}
        
      {:error, changeset} ->
        # Transaction will be rolled back
        {:error, Epic.add_error(epic, changeset: changeset)}
    end
  end
end
```

## Epic State Management

### Assigns

Share data between acts using assigns:

```elixir
# In first act
{:ok, Epic.assign(epic, :user_id, user.id)}

# In later act
user_id = epic.assigns[:user_id]

# Multiple assigns
{:ok, Epic.assign(epic, user: user, post: post, notified: true)}
```

### Smart Assigns

Use special keys for Epic behavior:

```elixir
# Return specific value from epic
Epic.assign(epic, :__epic_return__, result)

# Store context for debugging
Epic.assign(epic, :__context__, %{request_id: request_id})
```

## Testing Epics

### Unit Testing Acts

```elixir
defmodule MyApp.Acts.ProcessDataActTest do
  use ExUnit.Case
  alias Bonfire.Epics.{Epic, Act}
  
  test "processes data correctly" do
    epic = %Epic{assigns: %{data: "input"}}
    act = %Act{module: MyApp.Acts.ProcessDataAct}
    
    assert {:ok, result_epic} = MyApp.Acts.ProcessDataAct.run(epic, act)
    assert result_epic.assigns.processed == "INPUT"
  end
  
  test "handles missing data" do
    epic = %Epic{assigns: %{}}
    act = %Act{module: MyApp.Acts.ProcessDataAct}
    
    assert {:error, result_epic} = MyApp.Acts.ProcessDataAct.run(epic, act)
    assert [%{act: :process_data}] = result_epic.errors
  end
end
```

### Integration Testing

```elixir
test "complete workflow succeeds" do
  epic = Bonfire.Epics.from_config!(:create_post)
  
  assigns = %{
    current_user: fake_user!(),
    attrs: %{
      post_content: %{html_body: "Test post"},
      boundary: "public"
    }
  }
  
  assert {:ok, result} = Bonfire.Epics.run(epic, assigns)
  assert result.assigns.activity
  assert result.assigns.indexed
end
```

## Performance Patterns

### Conditional Act Execution

Skip acts based on conditions:

```elixir
defmodule MyApp.Acts.ConditionalAct do
  use Bonfire.Epics.Act
  
  @impl true
  def run(epic, act) do
    if should_run?(epic) do
      # Perform the action
      do_work(epic)
    else
      # Skip without error
      {:ok, epic}
    end
  end
  
  defp should_run?(%{assigns: %{skip_notifications: true}}), do: false
  defp should_run?(_), do: true
end
```

### Resource Cleanup

Ensure cleanup even on failure:

```elixir
defmodule MyApp.Acts.FileProcessingAct do
  use Bonfire.Epics.Act
  
  @impl true
  def run(epic, act) do
    temp_file = create_temp_file()
    
    try do
      result = process_file(temp_file)
      {:ok, Epic.assign(epic, :result, result)}
    rescue
      e ->
        {:error, Epic.add_error(epic, error: e)}
    after
      File.rm(temp_file)
    end
  end
end
```

## Common Patterns

### CRUD Operations

```elixir
# Create epic
config :my_app, :epics,
  create: [
    MyApp.Acts.ValidateAct,
    MyApp.Acts.CreateAct,
    MyApp.Acts.IndexAct,
    MyApp.Acts.NotifyAct
  ]

# Update epic  
config :my_app, :epics,
  update: [
    MyApp.Acts.LoadResourceAct,
    MyApp.Acts.AuthorizeAct,
    MyApp.Acts.UpdateAct,
    MyApp.Acts.ReindexAct
  ]
```

### Data Processing Pipeline

```elixir
config :my_app, :epics,
  process_upload: [
    MyApp.Acts.ValidateFileAct,
    [  # Parallel processing
      MyApp.Acts.ExtractMetadataAct,
      MyApp.Acts.GenerateThumbnailsAct,
      MyApp.Acts.ScanForVirusesAct
    ],
    MyApp.Acts.StoreFileAct,
    MyApp.Acts.UpdateRecordAct
  ]
```

### External Integration

```elixir
config :my_app, :epics,
  sync_external: [
    MyApp.Acts.FetchExternalDataAct,
    MyApp.Acts.TransformDataAct,
    MyApp.Acts.ValidateDataAct,
    MyApp.Acts.UpsertRecordsAct,
    {MyApp.Acts.NotifyAct, channels: [:email]}
  ]
```

## Debugging

### Enable Debug Output

```elixir
# In config
config :bonfire_epics, :debug, true

# Or at runtime
Application.put_env(:bonfire_epics, :debug, true)
```

### Debug Individual Acts

```elixir
defmodule MyApp.Acts.DebugAct do
  use Bonfire.Epics.Act
  import Bonfire.Epics.Debug
  
  @impl true
  def run(epic, act) do
    debug(epic.assigns, "Current assigns")
    debug(act.options, "Act options")
    
    # Your logic here
    {:ok, epic}
  end
end
```

### Inspect Epic State

```elixir
# After running
{:ok, epic} = Bonfire.Epics.run(epic, assigns)

IO.inspect(epic.assigns, label: "Final assigns")
IO.inspect(epic.errors, label: "Errors")
```

## Best Practices

### 1. Single Responsibility
Each Act should do one thing well:
```elixir
# Good: Focused acts
MyApp.Acts.ValidatePostAct
MyApp.Acts.CreatePostAct
MyApp.Acts.IndexPostAct

# Bad: Do-everything act
MyApp.Acts.HandlePostAct
```

### 2. Error Context
Always provide meaningful error context:
```elixir
{:error, Epic.add_error(epic,
  act: :process_image,
  step: :resize,
  error: :invalid_dimensions,
  details: %{width: width, height: height}
)}
```

### 3. Defensive Coding
Handle missing or invalid assigns:
```elixir
def run(%{assigns: %{user: nil}} = epic, act) do
  {:error, Epic.add_error(epic, act: :my_act, error: :user_required)}
end

def run(%{assigns: %{user: user}} = epic, act) do
  # Normal processing
end
```

### 4. Act Reusability
Design acts to be reusable across epics:
```elixir
# Configurable act
defmodule MyApp.Acts.NotifyAct do
  def run(epic, act) do
    template = act.options[:template] || :default
    delay = act.options[:delay] || 0
    # ...
  end
end
```

## Anti-Patterns to Avoid

### ❌ Side Effects in Guards
```elixir
# Bad
def run(epic, act) when send_email(epic.assigns.user) do

# Good  
def run(epic, act) do
  if should_send_email?(epic.assigns.user) do
    send_email(epic.assigns.user)
```

### ❌ Modifying Acts List
```elixir
# Bad - Don't modify epic.acts during execution
{:ok, %{epic | acts: epic.acts ++ [NewAct]}}

# Good - Use configuration or conditions
if condition, do: run_additional_act(epic)
```

### ❌ Catching All Errors
```elixir
# Bad - Hides real issues
def run(epic, act) do
  try do
    do_work(epic)
  rescue
    _ -> {:ok, epic}
  end
end

# Good - Handle specific cases
def run(epic, act) do
  case do_work(epic) do
    {:ok, result} -> {:ok, Epic.assign(epic, :result, result)}
    {:error, :not_found} -> {:ok, epic}  # Acceptable
    {:error, reason} -> {:error, Epic.add_error(epic, error: reason)}
  end
end
```

## Integration with Other Extensions

### Use Acts from Other Extensions

```elixir
config :my_app, :epics,
  create_social_post: [
    MyApp.Acts.ValidateContentAct,
    Bonfire.Social.Acts.PostContentsAct,
    Bonfire.Social.Acts.ThreadedAct,
    Bonfire.Social.Acts.FederateAct,
    MyApp.Acts.AnalyticsAct
  ]
```

### Register Your Acts

Make acts discoverable:

```elixir
# In your extension's config
config :bonfire_epics, :acts, [
  my_validate: MyApp.Acts.ValidateAct,
  my_process: MyApp.Acts.ProcessAct
]
```