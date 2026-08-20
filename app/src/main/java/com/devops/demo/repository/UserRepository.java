package com.devops.demo.repository;

import com.devops.demo.model.User;
import org.springframework.stereotype.Repository;

import java.util.Collection;
import java.util.Map;
import java.util.Optional;
import java.util.concurrent.ConcurrentHashMap;
import java.util.concurrent.atomic.AtomicLong;

/**
 * Simple in-memory, thread-safe repository.
 * This keeps the demo self-contained (no external DB required to run the app),
 * while still behaving like a realistic data access layer.
 */
@Repository
public class UserRepository {

    private final Map<Long, User> store = new ConcurrentHashMap<>();
    private final AtomicLong sequence = new AtomicLong(0);

    public UserRepository() {
        save(new User(null, "Alice Johnson", "alice@example.com"));
        save(new User(null, "Bob Smith", "bob@example.com"));
        save(new User(null, "Carla Diaz", "carla@example.com"));
    }

    public Collection<User> findAll() {
        return store.values();
    }

    public Optional<User> findById(Long id) {
        return Optional.ofNullable(store.get(id));
    }

    public User save(User user) {
        if (user.getId() == null) {
            user.setId(sequence.incrementAndGet());
        }
        store.put(user.getId(), user);
        return user;
    }

    public boolean deleteById(Long id) {
        return store.remove(id) != null;
    }
}
