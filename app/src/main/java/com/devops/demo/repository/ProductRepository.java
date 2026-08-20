package com.devops.demo.repository;

import com.devops.demo.model.Product;
import org.springframework.stereotype.Repository;

import java.math.BigDecimal;
import java.util.Collection;
import java.util.Map;
import java.util.Optional;
import java.util.concurrent.ConcurrentHashMap;
import java.util.concurrent.atomic.AtomicLong;

@Repository
public class ProductRepository {

    private final Map<Long, Product> store = new ConcurrentHashMap<>();
    private final AtomicLong sequence = new AtomicLong(0);

    public ProductRepository() {
        save(new Product(null, "Wireless Mouse", new BigDecimal("19.99"), "Electronics"));
        save(new Product(null, "Mechanical Keyboard", new BigDecimal("79.99"), "Electronics"));
        save(new Product(null, "Standing Desk", new BigDecimal("249.00"), "Furniture"));
    }

    public Collection<Product> findAll() {
        return store.values();
    }

    public Optional<Product> findById(Long id) {
        return Optional.ofNullable(store.get(id));
    }

    private Product save(Product product) {
        if (product.getId() == null) {
            product.setId(sequence.incrementAndGet());
        }
        store.put(product.getId(), product);
        return product;
    }
}
