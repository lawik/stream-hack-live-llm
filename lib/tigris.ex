defmodule Tigris do
  alias ExAws.S3
  def list!(prefix \\ "") do
    bucket!()
    |> S3.list_objects(prefix: prefix)
    |> ExAws.request!()
    |> then(fn %{body: %{contents: contents}} ->
      contents
    end)
  end

  def head!(key) do
    bucket!()
    |> S3.head_object(key)
    |> ExAws.request!()
  end

  def download!(%{key: key, size: size}, local_filepath) do
    opts = []

    {size, _} = Integer.parse(size)
    ref = :ets.new(:download, [:set, :public])
    :ets.insert(ref, {"download", {0,size}})
    IO.puts("Downloading #{key} to #{local_filepath}")
    progress(0, size)

    {t, _} = :timer.tc(fn ->
      bucket!()
      |> S3.download_file(key, :memory, opts)
      |> ExAws.stream!()
      |> Stream.map(fn chunk ->
        [{"download", {current, total}}] = :ets.lookup(ref, "download")
        new_size = current + byte_size(chunk)
        progress(new_size, total)
        :ets.insert(ref, {"download", {new_size, total}})
        chunk
      end)
      |> Stream.into(File.stream!(local_filepath))
      |> Stream.run()
    end)
    seconds = t / 1000 / 1000
    rate = Sizeable.filesize(size / seconds) <> "/s"
    IO.puts("Downloaded at: #{rate}")
    local_filepath
  end

  def download!(key, local_filepath) do
    %{status_code: 200, headers: headers} = head!(key)
    size = Enum.find(headers, fn {key, _} -> key == "Content-Length" end) |> elem(1)
    download!(%{key: key, size: size}, local_filepath)
  end

  @format [
      bar: " ",
      left: "",
      right: "",
      bar_color: [IO.ANSI.white, IO.ANSI.green_background],
      blank_color: IO.ANSI.blue_background,
      suffix: :bytes
    ]
  defp progress(size, total) do
    if size > 5 * 1024 * 1024 do
      #ProgressBar.render(size, total, @format)
      :ok
    end
  end

  def put!(key, data) do
    bucket!()
    |> S3.put_object(key, data)
    |> ExAws.request!()

    :ok
  end

  def put_file!(key, from_filepath) do
    from_filepath
    |> S3.Upload.stream_file()
    |> Stream.map(fn chunk ->
      IO.puts("uploading...")
      chunk
    end)
    |> S3.upload(bucket!(), key)
    |> ExAws.request!()
  end

  def put_tons!(kv) do
    kv
    |> Task.async_stream(fn {key, value} ->
      IO.puts(key)
      put!(key, value)
    end)
    |> Stream.run()
  end

  def objects_to_keys(objects), do:
    objects
    |> Enum.map(& &1.key)

  def exterminate! do
    stream =
      bucket!()
      |> S3.list_objects()
      |> ExAws.stream!()
      |> Stream.map(& &1.key)

    S3.delete_all_objects(bucket!(), stream) |> ExAws.request()

    :exterminated
  end

  def presign_get(key) do
    :s3
    |> ExAws.Config.new([])
    |> S3.presigned_url(:get, bucket!(), key, [])
  end

  def get(key, range \\ nil) do
    opts =
      if range do
        [range: "bytes=#{range}"]
      else
        []
      end

    result =
      bucket!()
      |> S3.get_object(key, opts)
      |> ExAws.request()

    case result do
      {:ok, %{body: body}} -> body
      {:error, {:http_error, 404, _}} -> nil
      {:error, error} -> {:error, error}
    end
  end

  defp bucket!, do: System.fetch_env!("BUCKET_NAME")
end
