# 🛒 Product Creation Example

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
