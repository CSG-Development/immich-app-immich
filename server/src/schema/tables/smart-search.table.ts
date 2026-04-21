import { AssetTable } from 'src/schema/tables/asset.table';
import { Column, ForeignKeyColumn, Index, Table } from 'src/sql-tools';

@Table({ name: 'smart_search' })
@Index({
  name: 'clip_index',
  using: 'hnsw',
  expression: `embedding vector_cosine_ops`,
  with: `ef_construction = 300, m = 16`,
  synchronize: false,
})
export class SmartSearchTable {
  @ForeignKeyColumn(() => AssetTable, { onDelete: 'CASCADE', primary: true })
  assetId!: string;

  @Column({ type: 'vector', length: 224, storage: 'external', synchronize: false }) // Original value: 512
  embedding!: string;
}
