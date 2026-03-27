defmodule AtomvmHttpServer.Static do
  # 404エラーページ
  def get_error_page(404) do
    {:error, 404}
  end

  # 405エラーページ
  def get_error_page(405) do
    {:error, 405}
  end

  # その他のエラー
  def get_error_page(status) do
    {:error, status}
  end

end
