defmodule LiveLlm.LLM do
    use GenServer
    @cache_path "/data/model-cache"
    #@tuned_model {:hf, "teknium/OpenHermes-2.5-Mistral-7B", cache_dir: @cache_path}
    @tuned_model {:hf, "NousResearch/Hermes-2-Pro-Mistral-7B", cache_dir: @cache_path}
    @base_model  {:hf, "mistralai/Mistral-7B-Instruct-v0.2", cache_dir: @cache_path}
    @object_cache_key "openhermes-2.5"

    def start_link(opts) do
        GenServer.start_link(__MODULE__, opts, name: __MODULE__)
    end

    def init(_opts) do
        state = %{serving: nil}
        {:ok, state, {:continue, :download}}
    end

    def generate(full_prompt) do
        Nx.Serving.batched_run(Hermes, full_prompt)
        |> Enum.to_list()
    end

    def handle_continue(:download, state) do
        @object_cache_key
        |> Tigris.list!()
        |> Enum.sort_by(& String.to_integer(&1.size), :asc)
        |> Enum.map(fn obj ->
            size = String.to_integer(obj.size)
            local_path = Path.join(@cache_path, Path.relative_to(obj.key, @object_cache_key))
            File.mkdir_p!(Path.dirname(local_path))
            case File.stat(local_path) do
                # Check that size is the same
                {:ok, %{size: ^size}} ->
                    :skip

                # Otherwise download
                _ ->
                    {t, _} = :timer.tc(fn ->
                        Tigris.download!(obj.key, local_path)
                    end)
                    seconds = t / 1000 / 1000
                    rate = Sizeable.filesize(size / seconds) <> "/s"
                    IO.puts("Downloaded at: #{rate}")
            end
        end)
        {:noreply, state, {:continue, :load_model}}
    end

    def handle_continue(:load_model, state) do
      IO.puts("start loading model...")
        Nx.global_default_backend(EXLA.Backend)

      IO.inspect(@tuned_model, label: "loading model")
      IO.puts("Loading spec...")
        {:ok, _spec} =
            Bumblebee.load_spec(@tuned_model,
              module: Bumblebee.Text.Mistral,
              architecture: :for_causal_language_modeling
            )
      IO.puts("Loading model info...")
        {:ok, model_info} = Bumblebee.load_model(@tuned_model, type: :bf16, backend: EXLA.Backend)
      IO.puts("Loading tokenizer...")
        {:ok, tokenizer} = Bumblebee.load_tokenizer(@base_model)
      IO.puts("Loading generator config...")
        {:ok, generation_config} =
            Bumblebee.load_generation_config(@tuned_model, spec_module: Bumblebee.Text.Mistral)

        generation_config =
            Bumblebee.configure(generation_config,
                max_new_tokens: 512,
                strategy: %{type: :multinomial_sampling, top_p: 0.6}
            )

      IO.puts("Creating serving...")
        serving =
            Bumblebee.Text.generation(model_info, tokenizer, generation_config,
                compile: [batch_size: 1, sequence_length: 1028],
                stream: true,
                defn_options: [compiler: EXLA]
            )

        {:ok, pid} = Nx.Serving.start_link(name: Hermes, serving: serving)
      IO.inspect(pid, label: "Hermes started")

        {:noreply, %{state | serving: pid}}
    end
end
