# 🛒 PART 1: Product Creation Example

This section demonstrates how to create a product with variations (e.g., color and size) using the proposed database structure.

---

## 1. Creating a Category

```sql
INSERT INTO categories (name, description)
VALUES ('Shoes', 'Footwear products');
```

---

## 2. Create a Product

```sql
INSERT INTO products (name, description, cost, price, main_sku, category_id)
VALUES (
    'Nike Air Max',
    'Running shoes',
    200.00,
    350.00,
    'NIKE123',
    1
);
```

---

## 3. Create Variation Types

```sql
INSERT INTO variation_types (name) VALUES ('Color');
INSERT INTO variation_types (name) VALUES ('Size');
```

---

## 4. Create Variation Values

```sql
-- Colors
INSERT INTO variation_values (variation_type_id, value) VALUES (1, 'Black');
INSERT INTO variation_values (variation_type_id, value) VALUES (1, 'White');

-- Sizes
INSERT INTO variation_values (variation_type_id, value) VALUES (2, '40');
INSERT INTO variation_values (variation_type_id, value) VALUES (2, '41');
```

---

## 5. Create a Product Variation

```sql
INSERT INTO product_variations (product_id, stock)
VALUES (1, 10);
```

---

## 6. Link Variation Items (THIS GENERATES THE SKU)

```sql
-- Example: Black Size 40
INSERT INTO product_variation_items (variation_id, variation_value_id)
VALUES (1, 1); -- Black

INSERT INTO product_variation_items (variation_id, variation_value_id)
VALUES (1, 3); -- Size 40
```

---

## Expected Result

After inserting the variation items, the system will automatically generate the SKU:

```
NIKE123-BLACK-40
```

---

## Important Note

Do NOT generate SKU when inserting into `product_variations`.

👉 The correct moment is after inserting variation items (color, size, etc.), otherwise the SKU will be incomplete.

---

## Summary

* Create product
* Create variation types
* Create variation values
* Create product variation
* Link variation items
* SKU is generated automatically

This flow ensures consistency and scalability for real-world ERP systems.

# 📦  PART 2: Inventory & Suppliers

This section introduces suppliers, stock locations, and inventory control.

---

## Suppliers

Stores supplier data.

### Example

```sql
INSERT INTO suppliers (name, phone, city, state)
VALUES ('Nike Supplier BR', '31999999999', 'Belo Horizonte', 'MG');
```

---

## Linking Supplier to Product

```sql
INSERT INTO supplier_products (supplier_id, product_id)
VALUES (1, 1);
```

---

## Stock Locations

Represents warehouses, stores, or distribution centers.

### Example

```sql
INSERT INTO stock_locations (name, city, state)
VALUES ('Main Warehouse', 'Belo Horizonte', 'MG');

INSERT INTO stock_locations (name, city, state)
VALUES ('Store Center', 'São Paulo', 'SP');
```

---

## Stock Structure

Stock is controlled per:

* Product variation
* Location

This allows:

* Multi-warehouse control
* Real-time inventory
* Accurate stock tracking

---

## Stock Movements

Inventory is updated through movements.

### Types

* `IN` → (stock increase)
* `OUT` → (stock decrease)
* `TRANSFER` → (local transference)

---

## Example: Stock Entry

```sql
INSERT INTO stock_movements (
    product_variation_id,
    destination_location_id,
    quantity,
    movement_type
) VALUES (
    1,
    1,
    50,
    'IN'
);
```

---

## Example: Stock

```sql
INSERT INTO stock_movements (
    product_variation_id,
    origin_location_id,
    quantity,
    movement_type
) VALUES (
    1,
    1,
    5,
    'OUT'
);
```

---

## Example: Transfer Between Locations

```sql
INSERT INTO stock_movements (
    product_variation_id,
    origin_location_id,
    destination_location_id,
    quantity,
    movement_type
) VALUES (
    1,
    1,
    2,
    10,
    'TRANSFER'
);
```

---

## Important Notes

* Do NOT update the `stock` table manually
* Always use `stock_movements`
* Stock is automatically updated via triggers

---

## Summary

* Suppliers linked to products
* Stock separated by location
* Movements control inventory
* Fully scalable ERP structure

This design supports real-world inventory systems used in e-commerce and retail.

