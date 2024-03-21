defmodule LiveLlmWeb.ChatLive do
    use LiveLlmWeb, :live_view

    def mount(_, _, socket) do
        {:ok, assign(socket, chat: Converse.new(), start: nil)}
    end

    def handle_event("query", %{"query" => query}, socket) do
        chat = socket.assigns.chat
        origin = self()
        Task.start(fn ->
            c = Converse.ask(chat, query)
            send(origin, {:chat, c})
        end)

        {:noreply, assign(socket, start: query)}
    end

    def handle_info({:chat, c}, socket) do
        Process.send_after(self(), :user, 2000)
        {:noreply, assign(socket, chat: c)}
    end

    def handle_info(:user, socket) do
        lv = self()
        Task.start(fn ->
            new_query =
                socket.assigns.chat
                |> Converse.mirror()
                |> Converse.ask("Write a good question to continue this conversation.")
                |> then(fn %{dialog: dialog} ->
                    {_, {_party, query}} = Enum.max_by(dialog, & elem(&1, 0))
                    query
                end)
            send(lv, {:query, new_query})
        end)
        {:noreply, socket}
    end

    def handle_info({:query, query}, socket) do
        chat = socket.assigns.chat
        origin = self()
        Task.start(fn ->
            c = Converse.ask(chat, query)
            send(origin, {:chat, c})
        end) 
        {:noreply, socket}
    end
    
    def render(assigns) do
        ~H"""
        <p><%= @chat.system %></p>
        <p :for={{index, {party, text}} <- @chat.dialog |> Enum.sort_by(& elem(&1, 0), :asc)} id={"chat-#{index}"}>
        <strong><%= party %>:</strong>&nbsp;<pre style="white-space: pre-wrap; word-wrap: break-word;"><%= text %></pre>
        </p>
        <form :if={@start == nil} phx-submit="query">
            <input type="text" name="query" id="query" />
        </form>
        """
    end
end