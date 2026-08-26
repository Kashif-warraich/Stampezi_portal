class AddActiveToShops < ActiveRecord::Migration[8.0]
  def change
    add_column :shops, :active, :boolean, null: false, default: true
  end
end
